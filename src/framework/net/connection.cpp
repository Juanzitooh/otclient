/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#ifndef __EMSCRIPTEN__

#include "connection.h"

#include "framework/util/stats.h"
#include "framework/core/graphicalapplication.h"

#include <openssl/ssl.h>
#include <openssl/x509v3.h>

asio::io_service g_ioService;
std::list<std::shared_ptr<asio::streambuf>> Connection::m_outputStreams;

Connection::Connection() :
    m_readTimer(g_ioService),
    m_writeTimer(g_ioService),
    m_delayedWriteTimer(g_ioService),
    m_resolver(g_ioService),
    m_socket(g_ioService),
    m_sslContext(asio::ssl::context::tls_client)
{
}

Connection::~Connection()
{
#ifndef NDEBUG
    assert(!g_app.isTerminated());
#endif
    close();
}

void Connection::poll()
{
	// reset must always be called prior to poll
	AutoStat s(STATS_MAIN, "PollConnection");
    g_ioService.reset();
    g_ioService.poll();
}

void Connection::terminate()
{
    g_ioService.stop();
    m_outputStreams.clear();
}

void Connection::close()
{
    if (!m_connected && !m_connecting)
        return;

    // flush send data before disconnecting on clean connections
    if (m_connected && !m_error && m_outputStream)
        internal_write();

    m_connecting = false;
    m_connected = false;
    m_connectCallback = nullptr;
    m_errorCallback = nullptr;
    m_recvCallback = nullptr;

    m_resolver.cancel();
    m_readTimer.cancel();
    m_writeTimer.cancel();
    m_delayedWriteTimer.cancel();

    if (m_secureSocket && m_secureSocket->lowest_layer().is_open()) {
        std::error_code ec;
        m_secureSocket->lowest_layer().shutdown(asio::ip::tcp::socket::shutdown_both, ec);
        m_secureSocket->lowest_layer().close();
    } else if (m_socket.is_open()) {
        std::error_code ec;
        m_socket.shutdown(asio::ip::tcp::socket::shutdown_both, ec);
        m_socket.close();
    }
}

void Connection::connect(const std::string_view host, const uint16_t port, const std::function<void()>& connectCallback)
{
    m_connected = false;
    m_connecting = true;
    m_error.clear();
    m_connectCallback = connectCallback;

    const asio::ip::tcp::resolver::query query(host.data(), stdext::unsafe_cast<std::string>(port));
    m_resolver.async_resolve(query, [capture0 = asConnection()](auto&& error, auto&& endpointIterator) {
        capture0->onResolve(std::move(error), std::move(endpointIterator));
    });

    m_readTimer.cancel();
    m_readTimer.expires_after(std::chrono::seconds(static_cast<uint32_t>(READ_TIMEOUT)));
    m_readTimer.async_wait([capture0 = asConnection()](auto&& error) {
        capture0->onTimeout(std::move(error));
    });
}

void Connection::connectSecure(const std::string_view host, const uint16_t port, const std::string_view caFile,
                               const std::function<void()>& connectCallback)
{
    [[maybe_unused]] const auto keepAlive = asConnection();
    m_connected = false;
    m_connecting = true;
    m_error.clear();
    m_useTls = true;
    m_secureHost = host;
    m_connectCallback = connectCallback;

    if (m_secureHost.empty() || caFile.empty()) {
        handleError(asio::error::invalid_argument);
        return;
    }

    std::error_code error;
    m_sslContext.set_options(asio::ssl::context::default_workarounds, error);
    if (error) {
        handleError(error);
        return;
    }

    m_sslContext.load_verify_file(std::string(caFile), error);
    if (error) {
        g_logger.error("Failed to load TLS CA file '{}': {}", caFile, error.message());
        handleError(error);
        return;
    }

    m_sslContext.set_verify_mode(asio::ssl::verify_peer, error);
    if (error) {
        handleError(error);
        return;
    }

    if (SSL_CTX_set_min_proto_version(m_sslContext.native_handle(), TLS1_2_VERSION) != 1) {
        handleError(asio::error::operation_not_supported);
        return;
    }

    if (m_secureSocket) {
        handleError(asio::error::already_started);
        return;
    }
    m_secureSocket = std::make_unique<asio::ssl::stream<asio::ip::tcp::socket>>(g_ioService, m_sslContext);

    std::error_code addressError;
    const auto address = asio::ip::make_address(m_secureHost, addressError);
    const bool isAddress = !addressError;
    if (isAddress && (address.is_unspecified() || address.is_multicast())) {
        handleError(asio::error::invalid_argument);
        return;
    }

    X509_VERIFY_PARAM* verifyParameters = SSL_get0_param(m_secureSocket->native_handle());
    X509_VERIFY_PARAM_set_hostflags(verifyParameters, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
    const int hostVerified = isAddress ?
        X509_VERIFY_PARAM_set1_ip_asc(verifyParameters, m_secureHost.c_str()) :
        X509_VERIFY_PARAM_set1_host(verifyParameters, m_secureHost.c_str(), m_secureHost.size());
    if (hostVerified != 1) {
        handleError(asio::error::invalid_argument);
        return;
    }

    if (!isAddress) {
        if (SSL_set_tlsext_host_name(m_secureSocket->native_handle(), m_secureHost.c_str()) != 1) {
            handleError(asio::error::invalid_argument);
            return;
        }
    }

    const asio::ip::tcp::resolver::query query(m_secureHost, stdext::unsafe_cast<std::string>(port));
    m_resolver.async_resolve(query, [capture0 = asConnection()](auto&& resolveError, auto&& endpointIterator) {
        capture0->onResolve(std::move(resolveError), std::move(endpointIterator));
    });

    m_readTimer.cancel();
    m_readTimer.expires_after(std::chrono::seconds(static_cast<uint32_t>(READ_TIMEOUT)));
    m_readTimer.async_wait([capture0 = asConnection()](auto&& timeoutError) {
        capture0->onTimeout(std::move(timeoutError));
    });
}

void Connection::internal_connect(const asio::ip::basic_resolver<asio::ip::tcp>::iterator& endpointIterator)
{
    auto connectHandler = [capture0 = asConnection()](auto&& PH1) {
        capture0->onConnect(std::forward<decltype(PH1)>(PH1));
    };
    if (m_useTls)
        m_secureSocket->lowest_layer().async_connect(*endpointIterator, connectHandler);
    else
        m_socket.async_connect(*endpointIterator, connectHandler);

    m_readTimer.cancel();
    m_readTimer.expires_from_now(asio::chrono::seconds(static_cast<uint32_t>(READ_TIMEOUT)));
    m_readTimer.async_wait([capture0 = asConnection()](auto&& PH1) {
        capture0->onTimeout(std::forward<decltype(PH1)>(PH1));
    });
}

void Connection::write(const uint8_t* buffer, const size_t size)
{
    if (!m_connected)
        return;

    // we can't send the data right away, otherwise we could create tcp congestion
    if (!m_outputStream) {
        if (!m_outputStreams.empty()) {
            m_outputStream = m_outputStreams.front();
            m_outputStreams.pop_front();
        } else
            m_outputStream = std::make_shared<asio::streambuf>();

        m_delayedWriteTimer.cancel();
        m_delayedWriteTimer.expires_from_now(asio::chrono::milliseconds(0));
        m_delayedWriteTimer.async_wait([capture0 = asConnection()](auto&& PH1) {
            capture0->onCanWrite(std::forward<decltype(PH1)>(PH1));
        });
    }

    std::ostream os(m_outputStream.get());
    os.write((const char*)buffer, size);
    os.flush();
}

void Connection::internal_write()
{
    if (!m_connected)
        return;

    std::shared_ptr<asio::streambuf> outputStream = m_outputStream;
    m_outputStream = nullptr;

    auto writeHandler = [capture0 = asConnection(), outputStream](auto&& PH1, auto&& PH2) {
        capture0->onWrite(std::forward<decltype(PH1)>(PH1), std::forward<decltype(PH2)>(PH2), outputStream);
    };
    if (m_useTls)
        async_write(*m_secureSocket, *outputStream, writeHandler);
    else
        async_write(m_socket, *outputStream, writeHandler);

    m_writeTimer.cancel();
    m_writeTimer.expires_from_now(asio::chrono::seconds(static_cast<uint32_t>(WRITE_TIMEOUT)));
    m_writeTimer.async_wait([capture0 = asConnection()](auto&& PH1) {
        capture0->onTimeout(std::forward<decltype(PH1)>(PH1));
    });
}

void Connection::read(const uint16_t bytes, const RecvCallback& callback)
{
    if (!m_connected)
        return;

    m_recvCallback = callback;

    auto readHandler = [capture0 = asConnection()](auto&& PH1, auto&& PH2) {
        capture0->onRecv(std::forward<decltype(PH1)>(PH1), std::forward<decltype(PH2)>(PH2));
    };
    if (m_useTls)
        async_read(*m_secureSocket, m_inputStream.prepare(bytes), readHandler);
    else
        async_read(m_socket, m_inputStream.prepare(bytes), readHandler);

    m_readTimer.cancel();
    m_readTimer.expires_from_now(asio::chrono::seconds(static_cast<uint32_t>(READ_TIMEOUT)));
    m_readTimer.async_wait([capture0 = asConnection()](auto&& PH1) {
        capture0->onTimeout(std::forward<decltype(PH1)>(PH1));
    });
}

void Connection::read_until(const std::string_view what, const RecvCallback& callback)
{
    if (!m_connected)
        return;

    m_recvCallback = callback;

    auto readHandler = [capture0 = asConnection()](auto&& PH1, auto&& PH2) {
        capture0->onRecv(std::forward<decltype(PH1)>(PH1), std::forward<decltype(PH2)>(PH2));
    };
    if (m_useTls)
        async_read_until(*m_secureSocket, m_inputStream, what, readHandler);
    else
        async_read_until(m_socket, m_inputStream, what, readHandler);

    m_readTimer.cancel();
    m_readTimer.expires_from_now(asio::chrono::seconds(static_cast<uint32_t>(READ_TIMEOUT)));
    m_readTimer.async_wait([capture0 = asConnection()](auto&& PH1) {
        capture0->onTimeout(std::forward<decltype(PH1)>(PH1));
    });
}

void Connection::read_some(const RecvCallback& callback)
{
    if (!m_connected)
        return;

    m_recvCallback = callback;

    auto readHandler = [capture0 = asConnection()](auto&& PH1, auto&& PH2) {
        capture0->onRecv(std::forward<decltype(PH1)>(PH1), std::forward<decltype(PH2)>(PH2));
    };
    if (m_useTls)
        m_secureSocket->async_read_some(m_inputStream.prepare(RECV_BUFFER_SIZE), readHandler);
    else
        m_socket.async_read_some(m_inputStream.prepare(RECV_BUFFER_SIZE), readHandler);

    m_readTimer.cancel();
    m_readTimer.expires_from_now(asio::chrono::seconds(static_cast<uint32_t>(READ_TIMEOUT)));
    m_readTimer.async_wait([capture0 = asConnection()](auto&& PH1) {
        capture0->onTimeout(std::forward<decltype(PH1)>(PH1));
    });
}

void Connection::onResolve(const std::error_code& error, const asio::ip::basic_resolver<asio::ip::tcp>::iterator&
                           endpointIterator)
{
    m_readTimer.cancel();

    if (error == asio::error::operation_aborted || !m_connecting)
        return;

    if (!error)
        internal_connect(endpointIterator);
    else {
        if (m_useTls)
            g_logger.error("Secure endpoint resolution for '{}' failed: {}", m_secureHost, error.message());
        handleError(error);
    }
}

void Connection::onConnect(const std::error_code& error)
{
    m_readTimer.cancel();

    if (error == asio::error::operation_aborted)
        return;

    if (error) {
        if (m_useTls)
            g_logger.error("Secure TCP connect to '{}' failed: {}", m_secureHost, error.message());
        handleError(error);
        return;
    }

    // disable nagle's algorithm, this make the game play smoother
    const asio::ip::tcp::no_delay option(true);
    if (m_useTls)
        m_secureSocket->lowest_layer().set_option(option);
    else
        m_socket.set_option(option);

    if (!m_useTls) {
        finishConnect();
        return;
    }

    m_readTimer.expires_from_now(asio::chrono::seconds(static_cast<uint32_t>(READ_TIMEOUT)));
    m_readTimer.async_wait([capture0 = asConnection()](auto&& timeoutError) {
        capture0->onTimeout(std::forward<decltype(timeoutError)>(timeoutError));
    });
    m_secureSocket->async_handshake(asio::ssl::stream_base::client,
                                   [capture0 = asConnection()](auto&& handshakeError) {
        capture0->onHandshake(std::forward<decltype(handshakeError)>(handshakeError));
    });
}

void Connection::onHandshake(const std::error_code& error)
{
    m_readTimer.cancel();
    if (error == asio::error::operation_aborted)
        return;

    if (error) {
        g_logger.error("TLS handshake with '{}' failed: {}", m_secureHost, error.message());
        handleError(error);
        return;
    }

    finishConnect();
}

void Connection::finishConnect()
{
    m_activityTimer.restart();
    m_connected = true;
    m_connecting = false;
    if (m_connectCallback)
        m_connectCallback();
}

void Connection::onCanWrite(const std::error_code& error)
{
    m_delayedWriteTimer.cancel();

    if (error == asio::error::operation_aborted)
        return;

    if (m_connected)
        internal_write();
}

void Connection::onWrite(const std::error_code& error, size_t, const std::shared_ptr<asio::streambuf>&
                         outputStream)
{
    m_writeTimer.cancel();

    if (error == asio::error::operation_aborted)
        return;

    // free output stream and store for using it again later
    outputStream->consume(outputStream->size());
    m_outputStreams.emplace_back(outputStream);

    if (m_connected && error)
        handleError(error);
}

void Connection::onRecv(const std::error_code& error, const size_t recvSize)
{
    m_readTimer.cancel();
    m_activityTimer.restart();

    if (error == asio::error::operation_aborted)
        return;

    if (m_connected) {
        if (!error) {
            if (m_recvCallback) {
                const auto* header = asio::buffer_cast<const char*>(m_inputStream.data());
                m_recvCallback((uint8_t*)header, recvSize);
            }
        } else
            handleError(error);
    }

    if (!error)
        m_inputStream.consume(recvSize);
}

void Connection::onTimeout(const std::error_code& error)
{
    if (error == asio::error::operation_aborted)
        return;

    handleError(asio::error::timed_out);
}

void Connection::handleError(const std::error_code& error)
{
    if (error == asio::error::operation_aborted)
        return;

    g_logger.error("{} connection to '{}' failed with error {}: {}",
                   m_useTls ? "Secure" : "Plain", m_secureHost, error.value(), error.message());
    m_error = error;
    if (m_errorCallback)
        m_errorCallback(error);
    if (m_connected || m_connecting)
        close();
}

int Connection::getIp()
{
    std::error_code error;
    const asio::ip::tcp::endpoint ip = m_useTls && m_secureSocket ?
        m_secureSocket->lowest_layer().remote_endpoint(error) : m_socket.remote_endpoint(error);
    if (!error)
        return asio::detail::socket_ops::host_to_network_long(ip.address().to_v4().to_ulong());

    g_logger.error("Getting remote ip");
    return 0;
}

#endif

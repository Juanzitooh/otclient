function isNetworkAddressResolutionError(errcode, errdesc)
    if errcode ~= 1 or type(errdesc) ~= 'string' then
        return false
    end

    local description = errdesc:lower()
    return description:find('host not found', 1, true) ~= nil or
        description:find('no address associated with hostname', 1, true) ~= nil or
        description:find('name or service not known', 1, true) ~= nil or
        description:find('nodename nor servname provided', 1, true) ~= nil
end

function translateNetworkError(errcode, connecting, errdesc)
    local text
    if errcode == 111 or errcode == 61 then
        text = tr('Connection refused, the server might be offline or restarting.\nPlease try again later.')
    elseif errcode == 110 then
        text = tr('Connection timed out. Either your network is failing or the server is offline.')
    elseif isNetworkAddressResolutionError(errcode, errdesc) then
        text = tr('Connection failed, the server address does not exist.')
    elseif connecting then
        text = tr('Connection failed.')
    else
        text = tr('Your connection has been lost.\nEither your network or the server went down.')
    end
    text = text .. ' ' .. tr('(ERROR %d)', errcode)
    return text
end

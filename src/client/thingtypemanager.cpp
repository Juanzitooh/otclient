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

#include "thingtypemanager.h"

#include <nlohmann/json.hpp>

#ifdef FRAMEWORK_EDITOR
#include <filesystem>
#include <fstream>
#include <limits>
#include <string_view>
#endif

#include "game.h"
#include "spriteappearances.h"
#include "thingtype.h"
#include "framework/core/filestream.h"
#include "framework/core/resourcemanager.h"
#include "framework/otml/otmldocument.h"
#ifdef FRAMEWORK_PROTOBUF
#include <appearances.pb.h>
#include <staticdata.pb.h>
#endif

#ifdef FRAMEWORK_EDITOR
#include "itemtype.h"
#include "creatures.h"
#include <framework/core/binarytree.h>
#endif


ThingTypeManager g_things;

#if defined(FRAMEWORK_EDITOR) && defined(FRAMEWORK_PROTOBUF)
namespace {

using AppearanceBank = google::protobuf::RepeatedPtrField<appearances::Appearance>;

const AppearanceBank* getAppearanceBank(const appearances::Appearances& library, const int category)
{
    switch (category) {
        case ThingCategoryItem: return &library.object();
        case ThingCategoryCreature: return &library.outfit();
        case ThingCategoryEffect: return &library.effect();
        case ThingCategoryMissile: return &library.missile();
        default: throw stdext::exception("invalid appearance category");
    }
}

AppearanceBank* getAppearanceBank(appearances::Appearances& library, const int category)
{
    switch (category) {
        case ThingCategoryItem: return library.mutable_object();
        case ThingCategoryCreature: return library.mutable_outfit();
        case ThingCategoryEffect: return library.mutable_effect();
        case ThingCategoryMissile: return library.mutable_missile();
        default: throw stdext::exception("invalid appearance category");
    }
}

std::filesystem::path getAppearanceEditorFile(const std::string& catalogPath, const int version)
{
    namespace fs = std::filesystem;
    if (version < 1500 || version >= 1600)
        throw stdext::exception("appearance editing is supported only for client versions 15.x");

    std::error_code error;
    const auto writeRoot = fs::canonical(g_resources.getWriteDir(), error);
    if (error)
        throw stdext::exception("unable to resolve the writable directory: {}", error.message());

    const auto package = writeRoot / "sprite-editor" / "data" / "things" / std::to_string(version);
    const auto catalog = package / "catalog-content.json";
    const auto ensureNoSymlinks = [&](const fs::path& target) {
        const auto relative = target.lexically_relative(writeRoot);
        if (relative.empty() || relative.is_absolute() || *relative.begin() == "..")
            throw stdext::exception("appearance editor path is outside the writable directory");

        auto current = writeRoot;
        for (const auto& part : relative) {
            current /= part;
            error.clear();
            const auto status = fs::symlink_status(current, error);
            if (error == std::errc::no_such_file_or_directory)
                continue;
            if (error)
                throw stdext::exception("unable to validate appearance editor path: {}", error.message());
            if (fs::is_symlink(status))
                throw stdext::exception("appearance work copies cannot contain symbolic links");
        }
    };

    ensureNoSymlinks(catalog);
    error.clear();
    if (!fs::is_regular_file(catalog, error) || error)
        throw stdext::exception("the active appearance catalog is not a regular file");
    const auto resolvedCatalog = fs::canonical(catalog, error);
    if (error)
        throw stdext::exception("unable to resolve the appearance catalog: {}", error.message());
    const auto activeCatalog = fs::canonical(catalogPath, error);
    if (error || resolvedCatalog != activeCatalog)
        throw stdext::exception("appearance editing is allowed only for the active work copy");

    std::ifstream catalogStream(catalog, std::ios::binary);
    if (!catalogStream)
        throw stdext::exception("unable to read the work copy catalog");
    const auto document = nlohmann::json::parse(catalogStream);

    std::string appearanceFile;
    for (const auto& entry : document) {
        if (entry.value("type", std::string{}) == "appearances") {
            appearanceFile = entry.at("file").get<std::string>();
            break;
        }
    }
    if (appearanceFile.empty())
        throw stdext::exception("the work copy catalog does not contain an appearances file");

    auto relativeFile = fs::path(appearanceFile).lexically_normal();
    if (relativeFile.empty() || relativeFile.is_absolute() || relativeFile.has_root_name() || relativeFile.has_root_directory())
        throw stdext::exception("invalid appearances file path in work copy catalog");
    for (const auto& part : relativeFile) {
        if (part == ".." || part == ".")
            throw stdext::exception("invalid appearances file path in work copy catalog");
    }

    const auto target = package / relativeFile;
    ensureNoSymlinks(target);
    error.clear();
    if (!fs::is_regular_file(target, error) || error)
        throw stdext::exception("the work copy appearances file is missing or invalid");
    return target;
}

appearances::Appearance* findAppearance(appearances::Appearances& library, const int category, const int id)
{
    for (auto& appearance : *getAppearanceBank(library, category)) {
        if (appearance.id() == static_cast<uint32_t>(id))
            return &appearance;
    }
    return nullptr;
}

const appearances::Appearance* findAppearance(const appearances::Appearances& library, const int category, const int id)
{
    for (const auto& appearance : *getAppearanceBank(library, category)) {
        if (appearance.id() == static_cast<uint32_t>(id))
            return &appearance;
    }
    return nullptr;
}

void collectAppearanceFields(const google::protobuf::Message& message, const std::string& prefix, nlohmann::json& booleans, nlohmann::json& values)
{
    const auto* descriptor = message.GetDescriptor();
    const auto* reflection = message.GetReflection();
    for (int index = 0; index < descriptor->field_count(); ++index) {
        const auto* field = descriptor->field(index);
        if (field->is_repeated())
            continue;
        const auto fieldName = std::string(field->name());
        const auto name = prefix.empty() ? fieldName : prefix + "." + fieldName;
        if (field->cpp_type() == google::protobuf::FieldDescriptor::CPPTYPE_MESSAGE) {
            collectAppearanceFields(reflection->GetMessage(message, field), name, booleans, values);
            continue;
        }

        switch (field->cpp_type()) {
            case google::protobuf::FieldDescriptor::CPPTYPE_BOOL:
                booleans[name] = reflection->GetBool(message, field);
                break;
            case google::protobuf::FieldDescriptor::CPPTYPE_INT32:
                values[name] = reflection->GetInt32(message, field);
                break;
            case google::protobuf::FieldDescriptor::CPPTYPE_INT64:
                values[name] = reflection->GetInt64(message, field);
                break;
            case google::protobuf::FieldDescriptor::CPPTYPE_UINT32:
                values[name] = reflection->GetUInt32(message, field);
                break;
            case google::protobuf::FieldDescriptor::CPPTYPE_UINT64:
                values[name] = reflection->GetUInt64(message, field);
                break;
            case google::protobuf::FieldDescriptor::CPPTYPE_ENUM:
                values[name] = reflection->GetEnumValue(message, field);
                break;
            default:
                break;
        }
    }
}

void setAppearanceScalar(google::protobuf::Message& message, const std::string& path, const nlohmann::json& value)
{
    const auto separator = path.find('.');
    const auto* descriptor = message.GetDescriptor();
    const auto* field = descriptor->FindFieldByName(path.substr(0, separator));
    if (!field || field->is_repeated())
        throw stdext::exception("unknown appearance property '{}'", path);

    auto* reflection = message.GetReflection();
    if (separator != std::string::npos) {
        if (field->cpp_type() != google::protobuf::FieldDescriptor::CPPTYPE_MESSAGE)
            throw stdext::exception("invalid appearance property path");
        setAppearanceScalar(*reflection->MutableMessage(&message, field), path.substr(separator + 1), value);
        return;
    }

    switch (field->cpp_type()) {
        case google::protobuf::FieldDescriptor::CPPTYPE_BOOL:
            if (!value.is_boolean()) throw stdext::exception("appearance flag '{}' must be boolean", path);
            reflection->SetBool(&message, field, value.get<bool>());
            return;
        case google::protobuf::FieldDescriptor::CPPTYPE_INT32:
            if (!value.is_number_integer()) throw stdext::exception("appearance value '{}' must be an integer", path);
            if (value.get<int64_t>() < std::numeric_limits<int32_t>::min() || value.get<int64_t>() > std::numeric_limits<int32_t>::max())
                throw stdext::exception("appearance value '{}' is out of range", path);
            reflection->SetInt32(&message, field, value.get<int32_t>());
            return;
        case google::protobuf::FieldDescriptor::CPPTYPE_INT64:
            if (!value.is_number_integer()) throw stdext::exception("appearance value '{}' must be an integer", path);
            reflection->SetInt64(&message, field, value.get<int64_t>());
            return;
        case google::protobuf::FieldDescriptor::CPPTYPE_UINT32:
            if (!value.is_number_unsigned() && (!value.is_number_integer() || value.get<int64_t>() < 0))
                throw stdext::exception("appearance value '{}' must be a non-negative integer", path);
            if (value.get<uint64_t>() > std::numeric_limits<uint32_t>::max())
                throw stdext::exception("appearance value '{}' is out of range", path);
            reflection->SetUInt32(&message, field, value.get<uint32_t>());
            return;
        case google::protobuf::FieldDescriptor::CPPTYPE_UINT64:
            if (!value.is_number_unsigned() && (!value.is_number_integer() || value.get<int64_t>() < 0))
                throw stdext::exception("appearance value '{}' must be a non-negative integer", path);
            reflection->SetUInt64(&message, field, value.get<uint64_t>());
            return;
        case google::protobuf::FieldDescriptor::CPPTYPE_ENUM: {
            if (!value.is_number_integer()) throw stdext::exception("appearance enum '{}' must be an integer", path);
            const auto number = value.get<int32_t>();
            const auto* enumValue = field->enum_type()->FindValueByNumber(number);
            if (!enumValue) throw stdext::exception("unknown value for appearance enum '{}'", path);
            reflection->SetEnum(&message, field, enumValue);
            return;
        }
        default:
            throw stdext::exception("appearance property '{}' is not an editable scalar", path);
    }
}

void readAppearancesFile(const std::filesystem::path& path, appearances::Appearances& library)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream || !library.ParseFromIstream(&stream))
        throw stdext::exception("could not parse the work copy appearances file");
}

void writeAppearancesFile(const std::filesystem::path& path, const appearances::Appearances& library)
{
    namespace fs = std::filesystem;
    const auto temporary = fs::path(path.string() + ".sprite-editor.tmp");
    const auto backup = fs::path(path.string() + ".sprite-editor.bak");
    std::error_code error;
    for (const auto& candidate : { temporary, backup }) {
        const auto status = fs::symlink_status(candidate, error);
        if (!error && fs::is_symlink(status))
            throw stdext::exception("appearance work copy contains an unsafe temporary path");
        if (error == std::errc::no_such_file_or_directory)
            error.clear();
        else if (error)
            throw stdext::exception("unable to validate appearance temporary path: {}", error.message());
    }
    if (fs::exists(backup, error)) {
        if (!fs::exists(path, error)) {
            fs::rename(backup, path, error);
            if (error) throw stdext::exception("could not recover the previous appearances file: {}", error.message());
        } else {
            fs::remove(backup, error);
        }
    }
    error.clear();
    fs::remove(temporary, error);
    std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
    if (!stream || !library.SerializeToOstream(&stream))
        throw stdext::exception("could not write the temporary appearances file");
    stream.flush();
    if (!stream)
        throw stdext::exception("could not flush the temporary appearances file");
    stream.close();

    appearances::Appearances verification;
    readAppearancesFile(temporary, verification);

    error.clear();
    fs::rename(path, backup, error);
    if (error)
        throw stdext::exception("could not stage the previous appearances file: {}", error.message());
    fs::rename(temporary, path, error);
    if (error) {
        std::error_code rollbackError;
        fs::rename(backup, path, rollbackError);
        throw stdext::exception("could not replace the appearances file: {}", error.message());
    }
    fs::remove(backup, error);
}

}
#endif

#ifdef FRAMEWORK_EDITOR
void ThingTypeManager::invalidateTextureCache()
{
    for (auto& category : m_thingTypes) {
        for (const auto& thingType : category) {
            if (thingType)
                thingType->unload();
        }
    }
}

std::string ThingTypeManager::getAppearanceEditorData(const int version, const int category, const int id)
{
#ifdef FRAMEWORK_PROTOBUF
    if (id < 1)
        throw stdext::exception("appearance ID must be positive");
    const auto path = getAppearanceEditorFile(m_catalogContentPath, version);
    appearances::Appearances library;
    readAppearancesFile(path, library);
    const auto* appearance = findAppearance(library, category, id);
    if (!appearance)
        throw stdext::exception("appearance {} was not found", id);

    nlohmann::json result = { { "bools", nlohmann::json::object() }, { "values", nlohmann::json::object() } };
    collectAppearanceFields(appearance->flags(), "", result["bools"], result["values"]);
    result["name"] = appearance->name();
    result["description"] = appearance->description();
    return result.dump();
#else
    throw stdext::exception("protobuf support is required to edit appearances");
#endif
}

bool ThingTypeManager::saveAppearanceEditorData(const int version, const int category, const int id, const std::string& changes)
{
#ifdef FRAMEWORK_PROTOBUF
    if (id < 1)
        throw stdext::exception("appearance ID must be positive");
    const auto updates = nlohmann::json::parse(changes);
    if (!updates.is_object())
        throw stdext::exception("appearance changes must be an object");

    const auto path = getAppearanceEditorFile(m_catalogContentPath, version);
    appearances::Appearances library;
    readAppearancesFile(path, library);
    auto* appearance = findAppearance(library, category, id);
    if (!appearance)
        throw stdext::exception("appearance {} was not found", id);

    const auto strings = updates.find("strings");
    if (strings != updates.end()) {
        if (!strings->is_object())
            throw stdext::exception("appearance changes section 'strings' must be an object");
        for (const auto* field : { "name", "description" }) {
            const auto it = strings->find(field);
            if (it == strings->end())
                continue;
            if (!it->is_string())
                throw stdext::exception("appearance field '{}' must be text", field);
            const auto value = it->get<std::string>();
            const size_t maximumLength = std::string_view(field) == "name" ? 128 : 512;
            if (value.size() > maximumLength)
                throw stdext::exception("appearance field '{}' is too long", field);
            if (std::string_view(field) == "name")
                appearance->set_name(value);
            else
                appearance->set_description(value);
        }
    }

    auto* flags = appearance->mutable_flags();
    for (const auto* section : { "bools", "values" }) {
        const auto it = updates.find(section);
        if (it == updates.end())
            continue;
        if (!it->is_object())
            throw stdext::exception("appearance changes section '{}' must be an object", section);
        for (auto field = it->begin(); field != it->end(); ++field)
            setAppearanceScalar(*flags, field.key(), field.value());
    }

    writeAppearancesFile(path, library);
    return true;
#else
    throw stdext::exception("protobuf support is required to edit appearances");
#endif
}

int ThingTypeManager::createAppearanceFromSprite(const int version, const int category, const int spriteId,
                                                 const std::string& name, const std::string& description)
{
#ifdef FRAMEWORK_PROTOBUF
    if (version < 1500 || version >= 1600)
        throw stdext::exception("appearance creation is supported only for client versions 15.x");
    if (spriteId < 1 || name.empty() || name.size() > 128 || description.size() > 512)
        throw stdext::exception("enter a sprite ID, a name up to 128 characters, and a description up to 512 characters");
    if (!g_spriteAppearances.getSheetBySpriteId(spriteId, false))
        throw stdext::exception("sprite {} is not part of the active work copy", spriteId);

    const auto path = getAppearanceEditorFile(m_catalogContentPath, version);
    appearances::Appearances library;
    readAppearancesFile(path, library);
    auto* bank = getAppearanceBank(library, category);
    uint32_t maximumId = 0;
    for (const auto& appearance : *bank)
        maximumId = std::max(maximumId, appearance.id());
    if (maximumId >= std::numeric_limits<uint16_t>::max())
        throw stdext::exception("the selected appearance category has no available 15.x IDs");

    const uint32_t id = maximumId + 1;
    auto* appearance = bank->Add();
    appearance->set_id(id);
    appearance->set_name(name);
    appearance->set_description(description);

    auto* frameGroup = appearance->mutable_frame_group()->Add();
    frameGroup->set_fixed_frame_group(category == ThingCategoryCreature
        ? appearances::FIXED_FRAME_GROUP_OUTFIT_IDLE
        : appearances::FIXED_FRAME_GROUP_OBJECT_INITIAL);
    frameGroup->set_id(0);
    auto* spriteInfo = frameGroup->mutable_sprite_info();
    spriteInfo->set_pattern_width(1);
    spriteInfo->set_pattern_height(1);
    spriteInfo->set_pattern_depth(1);
    spriteInfo->set_layers(1);
    spriteInfo->add_sprite_id(static_cast<uint32_t>(spriteId));

    writeAppearancesFile(path, library);
    return static_cast<int>(id);
#else
    throw stdext::exception("protobuf support is required to create appearances");
#endif
}
#endif

const nlohmann::json& ThingTypeManager::getCatalogContent(const std::string& file)
{
    const auto path = g_resources.resolvePath(g_resources.guessFilePath(file + "catalog-content", "json"));
    if (path != m_catalogContentPath || !m_catalogContent) {
        m_catalogContent = std::make_unique<nlohmann::json>(nlohmann::json::parse(g_resources.readFileContents(path)));
        m_catalogContentPath = path;
    }

    return *m_catalogContent;
}

void ThingTypeManager::clearCatalogContent()
{
    m_catalogContentPath.clear();
    m_catalogContent.reset();
}

void ThingTypeManager::init()
{
    m_nullThingType = std::make_shared<ThingType>();
    for (auto& m_thingType : m_thingTypes)
        m_thingType.resize(1, m_nullThingType);
#ifdef FRAMEWORK_EDITOR
    m_nullItemType = std::make_shared<ItemType>();
    m_itemTypes.resize(1, m_nullItemType);
#endif
}

void ThingTypeManager::terminate()
{
    for (auto& m_thingType : m_thingTypes)
        m_thingType.clear();

    m_nullThingType = nullptr;
    m_proficienciesFile.clear();
    m_proficiencyThingsCache.clear();
    m_proficiencyThingsCacheDirty = true;
    clearCatalogContent();

#ifdef FRAMEWORK_EDITOR
    m_itemTypes.clear();
    m_reverseItemTypes.clear();
    m_nullItemType = nullptr;
#endif
}

bool ThingTypeManager::loadDat(std::string file)
{
    m_datLoaded = false;
    m_datSignature = 0;
    m_contentRevision = 0;
    try {
        file = g_resources.guessFilePath(file, "dat");

        const auto& fin = g_resources.openFile(file);
        fin->cache(true);

        m_datSignature = fin->getU32();
        m_contentRevision = static_cast<uint16_t>(m_datSignature);

        for (auto& thingType : m_thingTypes) {
            const int count = fin->getU16() + 1;
            thingType.clear();
            thingType.resize(count, m_nullThingType);
        }

        for (int category = -1; ++category < ThingLastCategory;) {
            const uint16_t firstId = category == ThingCategoryItem ? 100 : 1;

            for (uint16_t id = firstId - 1, s = m_thingTypes[category].size(); ++id < s;) {
                const auto& type = std::make_shared<ThingType>();
                type->unserialize(id, static_cast<ThingCategory>(category), fin);
                m_thingTypes[category][id] = type;
            }
        }

        m_datLoaded = true;
        g_lua.callGlobalField("g_things", "onLoadDat", file);
        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("Failed to read dat '{}': {}'", file, e.what());
        return false;
    }
}

bool ThingTypeManager::loadOtml(std::string file)
{
    try {
        file = g_resources.guessFilePath(file, "otml");

        const auto& doc = OTMLDocument::parse(file);
        for (const auto& node : doc->children()) {
            ThingCategory category;
            if (node->tag() == "creatures")
                category = ThingCategoryCreature;
            else if (node->tag() == "items")
                category = ThingCategoryItem;
            else if (node->tag() == "effects")
                category = ThingCategoryEffect;
            else if (node->tag() == "missiles")
                category = ThingCategoryMissile;
            else {
                throw OTMLException(node, "not a valid thing category");
            }

            for (const auto& node2 : node->children()) {
                const auto id = stdext::safe_cast<uint16_t>(node2->tag());
                const auto& type = getThingType(id, category);
                if (!type)
                    throw OTMLException(node2, "thing not found");
                type->unserializeOtml(node2);
            }
        }
        return true;
    } catch (const std::exception& e) {
        g_logger.error("Failed to read dat otml '{}': {}'", file, e.what());
        return false;
    }
}

bool ThingTypeManager::loadAppearances(const std::string& file)
{
#ifdef FRAMEWORK_PROTOBUF
    m_catalogContent.reset();
    try {
        try {
            m_assetIdentifier = g_resources.readFileContents(g_resources.resolvePath(g_resources.guessFilePath(file + "assets", "json.sha256")));
        } catch (const std::exception& e) {
            m_assetIdentifier = "appearancesHash";
            g_logger.warning("Cannot load asset hash identifier from assets.json.sha256: {}", e.what());
        }

        if (!g_game.getFeature(Otc::GameLoadSprInsteadProtobuf)) {
            g_spriteAppearances.unload();
            int spritesCount = 0;
            std::string appearancesFile;
            const auto& document = getCatalogContent(file);
            for (const auto& obj : document) {
                const auto& type = obj["type"];
                if (type == "appearances") {
                    appearancesFile = obj["file"];
                } else if (type == "sprite") {
                    int lastSpriteId = obj["lastspriteid"].get<int>();
                    const auto& sheet = std::make_shared<SpriteSheet>(obj["firstspriteid"].get<int>(), lastSpriteId, static_cast<SpriteLayout>(obj["spritetype"].get<int>()), obj["file"].get<std::string>());
                    const int spritesPerSheet = sheet->getSpritesPerSheet();
                    const int maxSpriteId = sheet->firstId + spritesPerSheet - 1;
                    if (lastSpriteId > maxSpriteId) {
                        g_logger.debug("Sprite sheet '{}' lastspriteid {} exceeds capacity {}, clamping to {}", sheet->file, lastSpriteId, maxSpriteId, maxSpriteId);
                        lastSpriteId = maxSpriteId;
                        sheet->lastId = maxSpriteId;
                    }
                    g_spriteAppearances.addSpriteSheet(sheet);
                    spritesCount = std::max<int>(spritesCount, lastSpriteId);
                }
            }
            g_spriteAppearances.setSpritesCount(spritesCount + 1);
            g_spriteAppearances.setPath(file);
            // load appearances.dat
            std::stringstream fin;
            g_resources.readFileStream(g_resources.resolvePath(fmt::format("{}{}", file, appearancesFile)), fin);
            auto appearancesLib = appearances::Appearances();
            if (!appearancesLib.ParseFromIstream(&fin)) {
                throw stdext::exception("Couldn't parse appearances lib.");
            }
            for (int category = ThingCategoryItem; category < ThingLastCategory; ++category) {
                const google::protobuf::RepeatedPtrField<appearances::Appearance>* appearances = nullptr;
                switch (category) {
                    case ThingCategoryItem: appearances = &appearancesLib.object(); break;
                    case ThingCategoryCreature: appearances = &appearancesLib.outfit(); break;
                    case ThingCategoryEffect: appearances = &appearancesLib.effect(); break;
                    case ThingCategoryMissile: appearances = &appearancesLib.missile(); break;
                    default: return false;
                }
                // fix for custom asserts, where ids are not sorted.
                uint32_t lastAppearanceId = 0;
                for (const auto& appearance : *appearances) {
                    if (appearance.id() > lastAppearanceId)
                        lastAppearanceId = appearance.id();
                }
                auto& things = m_thingTypes[category];
                things.clear();
                things.resize(lastAppearanceId + 1, m_nullThingType);
                for (const auto& appearance : *appearances) {
                    const auto& type = std::make_shared<ThingType>();
                    const uint16_t id = appearance.id();
                    type->unserializeAppearance(id, static_cast<ThingCategory>(category), appearance);
                    m_thingTypes[category][id] = type;
                }
            }
            m_datLoaded = true;
            m_proficiencyThingsCacheDirty = true;
        } else {
            std::stringstream datFileStream;
            auto appearancesLib = appearances::Appearances();
            g_resources.readFileStream(g_resources.resolvePath(g_resources.guessFilePath(file, "dat")), datFileStream);
            if (!appearancesLib.ParseFromIstream(&datFileStream)) {
                throw stdext::exception("Couldn't parse appearances.dat.");
            }
            for (const auto& appearance : appearancesLib.object()) {
                const uint16_t id = appearance.id();
                if (auto* type = getRawThingType(id, ThingCategoryItem)) {
                    type->applyAppearanceFlags(appearance.flags());
                }
            }
        }
        return true;
    } catch (const std::exception& e) {
        g_logger.error("Failed to load '{}' (Appearances): {}", file, e.what());
        return false;
    }
#else
    g_logger.error("Protobuf not supported in this build. Enable FRAMEWORK_PROTOBUF");
    return false;
#endif
}

#ifdef FRAMEWORK_PROTOBUF
namespace {
    using RaceBank = google::protobuf::RepeatedPtrField<staticdata::Creature>;

    void loadCreatureBank(RaceList& otcRaceList, const RaceBank& protobufRaceList, bool boss) {
        for (const auto& protobufRace : protobufRaceList) {
            // add race to vector
            RaceType otcRaceType = RaceType();
            otcRaceType.raceId = protobufRace.raceid();
            otcRaceType.name = protobufRace.name();
            otcRaceType.hasCategory = protobufRace.has_category();
            otcRaceType.category = protobufRace.category();
            otcRaceType.boss = boss;

            Outfit otcOutfit;
            const auto& protobufOutfit = protobufRace.outfit();
            if (protobufOutfit.lookitem() != 0) {
                otcOutfit.setAuxId(static_cast<uint16_t>(protobufOutfit.lookitem()));
            } else {
                otcOutfit.setId(static_cast<uint16_t>(protobufOutfit.looktype()));
                otcOutfit.setAddons(static_cast<uint8_t>(protobufOutfit.lookaddons()));
                if (protobufOutfit.has_colors()) {
                    const auto& pbColors = protobufOutfit.colors();
                    otcOutfit.setHead(static_cast<uint8_t>(pbColors.head()));
                    otcOutfit.setBody(static_cast<uint8_t>(pbColors.body()));
                    otcOutfit.setLegs(static_cast<uint8_t>(pbColors.legs()));
                    otcOutfit.setFeet(static_cast<uint8_t>(pbColors.feet()));
                }
            }

            otcRaceType.outfit = std::move(otcOutfit);
            otcRaceList.emplace_back(std::move(otcRaceType));
        }
    }
}

bool ThingTypeManager::loadStaticData(const std::string& file)
{
    try {
        std::string staticDataFile;

        const auto& document = getCatalogContent(file);
        for (const auto& obj : document) {
            const auto& type = obj["type"];
            if (type == "staticdata") {
                staticDataFile = obj["file"];
            }
        }

        // load staticdata.dat
        std::stringstream datFileStream;
        g_resources.readFileStream(g_resources.resolvePath(fmt::format("{}{}", file, staticDataFile)), datFileStream);
        auto staticDataLib = staticdata::Staticdata();
        if (!staticDataLib.ParseFromIstream(&datFileStream)) {
            throw stdext::exception("Couldn't parse staticdata lib.");
        }

        // if reload, start again
        m_monsterRaces.clear();

        const auto& raceBank = staticDataLib.monsters();
        const auto& bossBank = staticDataLib.bosses();
        m_monsterRaces.reserve(static_cast<size_t>(raceBank.size()) + bossBank.size());

        // load monsters and bosses
        // note: aside from compatibility with the QT client,
        // there is no need to have monsters and bosses
        // in separate data banks
        loadCreatureBank(m_monsterRaces, raceBank, false);
        loadCreatureBank(m_monsterRaces, bossBank, true);
        return true;
    } catch (const std::exception& e) {
        g_logger.error("Failed to load '{}' (StaticData): {}", file, e.what());
        return false;
    }

    return false;
}
#else
bool ThingTypeManager::loadStaticData(const std::string& file)
{
    g_logger.error("Protobuf not supported in this build. Enable FRAMEWORK_PROTOBUF");
    return false;
}
#endif

bool ThingTypeManager::resolveProficienciesFile(const std::string& file)
{
    m_proficienciesFile.clear();

    if (!g_game.getFeature(Otc::GameProficiency)) {
        return false;
    }

    try {
        std::string proficienciesFile;

        const auto& document = getCatalogContent(file);
        for (const auto& obj : document) {
            const auto& type = obj["type"];
            if (type == "proficiencies") {
                proficienciesFile = obj["file"];
            }
        }

        if (proficienciesFile.empty()) {
            return false;
        }

        const auto proficienciesPath = fmt::format("{}{}", file, proficienciesFile);
        if (!g_resources.fileExists(proficienciesPath)) {
            return false;
        }

        m_proficienciesFile = proficienciesPath;
        return true;
    } catch (const std::exception&) {
        m_proficienciesFile.clear();
        return false;
    }
}

const ThingTypeList& ThingTypeManager::getThingTypes(const ThingCategory category)
{
    if (category < ThingLastCategory)
        return m_thingTypes[category];

    throw Exception("invalid thing type category {}", category);
}

const ThingTypePtr& ThingTypeManager::getThingType(const uint16_t id, const ThingCategory category)
{
    if (category >= ThingLastCategory || id >= m_thingTypes[category].size()) {
        g_logger.error("Invalid thing type client id {} in category {}", id, static_cast<uint8_t>(category));
        return m_nullThingType;
    }
    return m_thingTypes[category][id];
}

ThingType* ThingTypeManager::getRawThingType(uint16_t id, ThingCategory category) {
    if (category >= ThingLastCategory || id >= m_thingTypes[category].size()) {
        g_logger.error("Invalid thing type client id {} in category {}", id, static_cast<uint8_t>(category));
        return nullptr;
    }
    return m_thingTypes[category][id].get();
}

ThingTypeList ThingTypeManager::findThingTypeByAttr(const ThingAttr attr, const ThingCategory category)
{
    ThingTypeList ret;
    for (const auto& type : m_thingTypes[category])
        if (type->hasAttr(attr))
            ret.emplace_back(type);
    return ret;
}

void ThingTypeManager::buildProficiencyCache()
{
    m_proficiencyThingsCache.clear();
    for (const auto& type : m_thingTypes[ThingCategoryItem]) {
        if (type && type->getProficiencyId() > 0) {
            m_proficiencyThingsCache.emplace_back(type);
        }
    }
    m_proficiencyThingsCacheDirty = false;
}

const ThingTypeList& ThingTypeManager::getProficiencyThings()
{
    if (m_proficiencyThingsCacheDirty) {
        buildProficiencyCache();
    }
    return m_proficiencyThingsCache;
}

std::string ThingTypeManager::getCyclopediaItemName(uint16_t id)
{
    const auto& type = getThingType(id, ThingCategoryItem);
    if (type->isNull()) return "";
    if (!type->getMarketData().name.empty()) return type->getMarketData().name;
    return type->getName();
}

std::string ThingTypeManager::getProficienciesFile()
{
    if (!g_game.getFeature(Otc::GameProficiency)) {
        return "";
    }

    if (!m_proficienciesFile.empty() && g_resources.fileExists(m_proficienciesFile)) {
        return m_proficienciesFile;
    }

    return "";
}

const RaceType& ThingTypeManager::getRaceData(uint32_t raceId)
{
    for (const auto& raceData : m_monsterRaces) {
        if (raceData.raceId == raceId) {
            return raceData;
        }
    }

    return emptyRaceType;
}

RaceList ThingTypeManager::getRacesByName(const std::string& searchString)
{
    RaceList result;
    for (const auto& race : m_monsterRaces) {
        if (race.name.find(searchString) != std::string::npos) {
            result.push_back(race);
        }
    }
    return result;
}

#ifdef FRAMEWORK_EDITOR
void ThingTypeManager::parseItemType(uint16_t serverId, pugi::xml_node node)
{
    bool s;
    int d;

    if (g_game.getClientVersion() < 960) {
        s = serverId > 20000 && serverId < 20100;
        d = 20000;
    } else {
        s = serverId > 30000 && serverId < 30100;
        d = 30000;
    }

    ItemTypePtr itemType;
    if (s) {
        serverId -= d;
        itemType = std::make_shared<ItemType>();
        itemType->setServerId(serverId);
        addItemType(itemType);
    } else
        itemType = getItemType(serverId);

    itemType->setName(node.attribute("name").as_string());
    for (auto attrib : node.children()) {
        std::string key = attrib.attribute("key").as_string();
        if (key.empty())
            continue;

        stdext::tolower(key);
        if (key == "description")
            itemType->setDesc(attrib.attribute("value").as_string());
        else if (key == "weapontype")
            itemType->setCategory(ItemCategoryWeapon);
        else if (key == "ammotype")
            itemType->setCategory(ItemCategoryAmmunition);
        else if (key == "armor")
            itemType->setCategory(ItemCategoryArmor);
        else if (key == "charges")
            itemType->setCategory(ItemCategoryCharges);
        else if (key == "type") {
            std::string value = attrib.attribute("value").as_string();
            stdext::tolower(value);

            if (value == "key")
                itemType->setCategory(ItemCategoryKey);
            else if (value == "magicfield")
                itemType->setCategory(ItemCategoryMagicField);
            else if (value == "teleport")
                itemType->setCategory(ItemCategoryTeleport);
            else if (value == "door")
                itemType->setCategory(ItemCategoryDoor);
        }
    }
}

void ThingTypeManager::addItemType(const ItemTypePtr& itemType)
{
    const uint16_t id = itemType->getServerId();
    if (unlikely(id >= m_itemTypes.size()))
        m_itemTypes.resize(id + 1, m_nullItemType);
    m_itemTypes[id] = itemType;
}

const ItemTypePtr& ThingTypeManager::findItemTypeByClientId(uint16_t id)
{
    if (id == 0 || id >= m_reverseItemTypes.size())
        return m_nullItemType;

    if (m_reverseItemTypes[id])
        return m_reverseItemTypes[id];
    return m_nullItemType;
}

const ItemTypePtr& ThingTypeManager::findItemTypeByName(const std::string& name)
{
    for (const ItemTypePtr& it : m_itemTypes)
        if (it->getName() == name)
            return it;
    return m_nullItemType;
}

ItemTypeList ThingTypeManager::findItemTypesByName(const std::string& name)
{
    ItemTypeList ret;
    for (const ItemTypePtr& it : m_itemTypes)
        if (it->getName() == name)
            ret.emplace_back(it);
    return ret;
}

ItemTypeList ThingTypeManager::findItemTypesByString(const std::string& name)
{
    ItemTypeList ret;
    for (const ItemTypePtr& it : m_itemTypes)
        if (it->getName().find(name) != std::string::npos)
            ret.emplace_back(it);
    return ret;
}

const ItemTypePtr& ThingTypeManager::getItemType(uint16_t id)
{
    if (id >= m_itemTypes.size() || m_itemTypes[id] == m_nullItemType) {
        g_logger.error("Invalid thing type, server id: {}", id);
        return m_nullItemType;
    }
    return m_itemTypes[id];
}

ItemTypeList ThingTypeManager::findItemTypeByCategory(ItemCategory category)
{
    ItemTypeList ret;
    for (const ItemTypePtr& type : m_itemTypes)
        if (type->getCategory() == category)
            ret.emplace_back(type);
    return ret;
}

void ThingTypeManager::saveDat(const std::string& fileName)
{
    if (!m_datLoaded)
        throw Exception("failed to save, dat is not loaded");

    try {
        const auto& fin = g_resources.createFile(fileName);
        if (!fin)
            throw Exception("failed to open file '{}' for write", fileName);

        fin->cache();

        fin->addU32(m_datSignature);

        for (const auto& m_thingType : m_thingTypes)
            fin->addU16(m_thingType.size() - 1);

        for (int category = 0; category < ThingLastCategory; ++category) {
            uint16_t firstId = 1;
            if (category == ThingCategoryItem)
                firstId = 100;

            for (uint16_t id = firstId; id < m_thingTypes[category].size(); ++id)
                m_thingTypes[category][id]->serialize(fin);
        }

        fin->flush();
        fin->close();
    } catch (const std::exception& e) {
        g_logger.error("Failed to save '{}': {}", fileName, e.what());
    }
}

void ThingTypeManager::loadOtb(const std::string& file)
{
    try {
        const auto& fin = g_resources.openFile(file);
        fin->cache();

        uint32_t signature = fin->getU32();
        if (signature != 0)
            throw Exception("invalid otb file");

        const auto& root = fin->getBinaryTree();
        root->skip(1); // otb first byte is always 0

        signature = root->getU32();
        if (signature != 0)
            throw Exception("invalid otb file");

        if (const uint8_t rootAttr = root->getU8(); rootAttr == 0x01) { // OTB_ROOT_ATTR_VERSION
            if (const uint16_t size = root->getU16(); size != 4 + 4 + 4 + 128)
                throw Exception("invalid otb root attr version size");

            m_otbMajorVersion = root->getU32();
            m_otbMinorVersion = root->getU32();
            root->skip(4); // buildNumber
            root->skip(128); // description
        }

        const BinaryTreeVec children = root->getChildren();
        m_reverseItemTypes.clear();
        m_itemTypes.resize(children.size() + 1, m_nullItemType);
        m_reverseItemTypes.resize(children.size() + 1, m_nullItemType);

        for (const auto& node : children) {
            const auto& itemType = std::make_shared<ItemType>();
            itemType->unserialize(node);
            addItemType(itemType);

            const uint16_t clientId = itemType->getClientId();
            if (unlikely(clientId >= m_reverseItemTypes.size()))
                m_reverseItemTypes.resize(clientId + 1);
            m_reverseItemTypes[clientId] = itemType;
        }

        m_otbLoaded = true;
        g_lua.callGlobalField("g_things", "onLoadOtb", file);
    } catch (const std::exception& e) {
        g_logger.error("Failed to load '{}' (OTB file): {}", file, e.what());
    }
}

void ThingTypeManager::loadXml(const std::string& file)
{
    try {
        if (!isOtbLoaded())
            throw Exception("OTB must be loaded before XML");

        pugi::xml_document doc;
        pugi::xml_parse_result result = doc.load_file(file.c_str());
        if (!result)
            throw Exception("failed to parse '{}': '{}'", file, result.description());

        pugi::xml_node root = doc.child("items");
        if (root.empty())
            throw Exception("invalid root tag name");

        for (pugi::xml_node element = root.first_child(); element; element = element.next_sibling()) {
            if (element.name() != std::string("item"))
                continue;

            const auto id = element.attribute("id").as_uint();
            if (id != 0) {
                std::vector<std::string> s_ids = stdext::split(element.attribute("id").as_string(), ";");
                for (const std::string& s : s_ids) {
                    std::vector<int32_t> ids = stdext::split<int32_t>(s, "-");
                    if (ids.size() > 1) {
                        int32_t i = ids[0];
                        while (i <= ids[1])
                            parseItemType(++i, element);
                    } else
                        parseItemType(atoi(s.c_str()), element);
                }
            } else {
                std::vector<int32_t> begin = stdext::split<int32_t>(element.attribute("fromid").as_string(), ";");
                std::vector<int32_t> end = stdext::split<int32_t>(element.attribute("toid").as_string(), ";");
                if (begin[0] && begin.size() == end.size()) {
                    const size_t size = begin.size();
                    for (size_t i = 0; i < size; ++i)
                        while (begin[i] <= end[i])
                            parseItemType(++begin[i], element);
                }
            }
        }

        m_xmlLoaded = true;
        g_logger.debug("Items.xml read successfully.");
    } catch (const std::exception& e) {
        g_logger.error("Failed to load '{}' (XML file): {}", file, e.what());
    }
}

#endif

/* vim: set ts=4 sw=4 et: */

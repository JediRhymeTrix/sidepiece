#include "../src/core.hpp"
int wmain() {
    try {
        unsigned count = 0;
        auto check = [&](bool b) {
            require(b, "configurable rule assertion failed");
            ++count;
        };
        string config =
            R"({"schemaVersion":1,"enabled":true,"whitelistDeviceIds":["ABCD_10DE_0000_0000_1"],"blacklistDeviceIds":[],"whitelistEndpoints":["customMetadata"],"blacklistEndpoints":[],"rules":[{"endpoint":"customMetadata","method":"GET","overrides":[{"field":"mode","from":"old","to":"a longer value"},{"field":"flag","from":true,"to":false}]}]})";
        Rules rules = parseRules(config);
        string payload =
            R"({ "dIDa":["abcd_10de_0000_0000_1"],"mode":"old","flag":true,"untouched":"%/" })";
        string path = driverPrefix + "customMetadata/" + encodeReplacement(payload),
               original = path;
        check(rewrite(path, rules));
        string expected =
            R"({ "dIDa":["abcd_10de_0000_0000_1"],"mode":"a longer value","flag":false,"untouched":"%/" })";
        check(unescape(path.substr((driverPrefix + "customMetadata/").size())) == expected);
        check(!rewrite(original, rules, "POST"));
        rules.deny.insert("ABCD_10DE_0000_0000_1");
        check(!rewrite(original, rules));
        for (
            string bad :
            {string(R"({"rules":false})"),
             string(R"({"rules":[]})"),
             string(R"({"schemaVersion":1,"rules":false})"),
             string(R"({"schemaVersion":2,"rules":[]})"),
             string(
                 R"({"schemaVersion":1,"rules":[{"endpoint":"x","method":"POST","overrides":[]}]})"),
             string(
                 R"({"schemaVersion":1,"rules":[{"endpoint":"x","method":"GET","overrides":[{"field":"dIDa","from":1,"to":2}]}]})")}) {
            bool rejected = false;
            try {
                parseRules(bad);
            } catch (...) {
                rejected = true;
            }
            check(rejected);
        }
        wchar_t temp[MAX_PATH]{}, name[MAX_PATH]{};
        require(GetTempPathW(MAX_PATH, temp) && GetTempFileNameW(temp, L"spt", 0, name),
                "fixture temp failed");
        DeleteFileW(name);
        require(CreateDirectoryW(name, nullptr) != 0, "fixture mkdir failed");
        dir = name;
        localBase = "http://localhost/synthetic/";
        files[0] = dir + L"\\localized.json";
        files[1] = dir + L"\\profiles.json";
        string loc =
            R"({"localizedConfig":{"gfwsl":{"server":"https://gfwsl.geforce.com/"}},"configTimestamp":"preserve"})";
        string profiles =
            R"([{"componentName":"grd","updateCheckerProfiles":[{"otaBaseUrl":"https://gfwsl.geforce.com/"}]},{"componentName":"crd","updateCheckerProfiles":[{"otaBaseUrl":"https://gfwsl.geforce.com/"}]}])";
        for (int i = 0; i < 2; ++i) {
            Handle f(CreateFileW(files[i].c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                                 FILE_ATTRIBUTE_NORMAL, nullptr));
            require(f.h != INVALID_HANDLE_VALUE, "fixture create failed");
            writeAll(f.h, i ? profiles : loc);
        }
        updateEndpoints(true);
        check(readFile(files[0]) != loc);
        updateEndpoints(false);
        check(readFile(files[0]) == loc && readFile(files[1]) == profiles);
        updateEndpoints(false);
        check(readFile(files[0]) == loc);
        atomicReplace(files[1], profiles, "[]");
        bool failed = false;
        try {
            updateEndpoints(true);
        } catch (...) {
            failed = true;
        }
        check(failed && readFile(files[0]) == loc);
        for (const auto &p : files)
            DeleteFileW(p.c_str());
        DeleteFileW((dir + L"\\backups\\LocalizedConfig.json.native-original").c_str());
        DeleteFileW((dir + L"\\backups\\component_profiles.json.native-original").c_str());
        RemoveDirectoryW((dir + L"\\backups").c_str());
        RemoveDirectoryW(dir.c_str());
        std::printf("configurable rules/transaction fixtures: %u checks passed\n", count);
        return 0;
    } catch (const std::exception &e) {
        std::fprintf(stderr, "%s\n", e.what());
        return 1;
    }
}

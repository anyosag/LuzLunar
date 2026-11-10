// Unit tests for app/fork/pcorderrules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/pcorderrules_test.cpp
#include "fork/pcorderrules.h"

#include <cstdio>

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

using namespace PcOrderRules;
using Pcs = std::vector<std::pair<std::string, std::string>>;
using List = std::vector<std::string>;

static Pcs samplePcs()
{
    return { { "u1", "Office" }, { "u2", "gonzalo" }, { "u3", "Living Room" }, { "u4", "Studio" } };
}

static void testSortByName()
{
    CHECK(sorted(samplePcs(), "", {}) == (List{ "u2", "u3", "u1", "u4" }));
    CHECK(sorted({}, "", {}).empty());
    // Same name (any case): input order
    CHECK(sorted({ { "a", "MSH" }, { "b", "msh" }, { "c", "Msh" } }, "", {}) == (List{ "a", "b", "c" }));
}

static void testKeepFirst()
{
    CHECK(sorted(samplePcs(), "u4", {}) == (List{ "u4", "u2", "u3", "u1" }));
    // Not among the PCs: ignored
    CHECK(sorted(samplePcs(), "zz", {}) == (List{ "u2", "u3", "u1", "u4" }));
    // Kept first wins over its place in the order
    CHECK(sorted(samplePcs(), "u4", { "u1", "u4", "u2" }) == (List{ "u4", "u1", "u2", "u3" }));
}

static void testOrder()
{
    CHECK(sorted(samplePcs(), "", { "u4", "u1" }) == (List{ "u4", "u1", "u2", "u3" }));
    CHECK(sorted(samplePcs(), "", { "u4", "u3", "u2", "u1" }) == (List{ "u4", "u3", "u2", "u1" }));
}

static void testUnknownAndDuplicates()
{
    CHECK(sorted(samplePcs(), "", { "nope", "u1", "u1", "gone", "u4", "u1" }) == (List{ "u1", "u4", "u2", "u3" }));
    // A new PC (not in the order) goes after the ordered ones
    CHECK(sorted(samplePcs(), "", { "u3", "u1" }) == (List{ "u3", "u1", "u2", "u4" }));
}

static void testMoved()
{
    const List l = { "a", "b", "c", "d" };
    CHECK(moved(l, 0, 3) == (List{ "b", "c", "d", "a" }));
    CHECK(moved(l, 3, 0) == (List{ "d", "a", "b", "c" }));
    CHECK(moved(l, 1, 2) == (List{ "a", "c", "b", "d" }));
    CHECK(moved(l, 2, 2) == l);
    CHECK(moved(l, 4, 0) == l);
    CHECK(moved(l, 0, 4) == l);
    CHECK(moved({}, 0, 0).empty());
}

static void testDropsKeepFirst()
{
    CHECK(!dropsKeepFirst({ "a", "b" }, ""));
    CHECK(!dropsKeepFirst({}, "a"));
    CHECK(!dropsKeepFirst({ "a", "b" }, "a"));
    CHECK(dropsKeepFirst({ "b", "a" }, "a"));
    CHECK(dropsKeepFirst({ "b" }, "a"));
}

int main()
{
    testSortByName();
    testKeepFirst();
    testOrder();
    testUnknownAndDuplicates();
    testMoved();
    testDropsKeepFirst();

    if (s_Failures == 0) {
        std::printf("pcorderrules: all tests passed\n");
        return 0;
    }
    std::printf("pcorderrules: %d failure(s)\n", s_Failures);
    return 1;
}

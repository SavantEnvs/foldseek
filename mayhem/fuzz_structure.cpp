// libFuzzer harness over foldseek's structure input path (what `foldseek createdb` runs on every
// file or tar entry): GemmiWrapper::loadFromBuffer and, in the createdb mode, the per-chain
// backbone rebuild (PULCHRA) and 3Di encoding that structcreatedb.cpp does with the parsed arrays.
// One source, one binary per FS_MODE (see build.sh).
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "GemmiWrapper.h"
#include "PulchraWrapper.h"
#include "structureto3di.h"

#define FS_PDB 1
#define FS_MMCIF 2
#define FS_MMJSON 3
#define FS_CHEMCOMP 4
#define FS_FOLDCOMP 5
#define FS_ZSTD 6
#define FS_GZIP 7
#define FS_CREATEDB 8

#ifndef FS_MODE
#error "FS_MODE must be defined"
#endif

// both objects are locals: PulchraWrapper keeps calloc'd coordinate rows sized by the largest chain seen,
// so a process-lifetime instance would make one input's result depend on earlier inputs
static void runCreatedbPipeline(GemmiWrapper &gw) {
    StructureTo3Di structureTo3Di;
    PulchraWrapper pulchra;
    for (size_t ch = 0; ch < gw.chain.size(); ch++) {
        size_t chainStart = gw.chain[ch].first;
        size_t chainLen = gw.chain[ch].second - chainStart;
        if (chainLen <= 3) {
            continue;
        }
        bool allX = true;
        for (size_t pos = 0; pos < chainLen; pos++) {
            const char aa = gw.ami[chainStart + pos];
            if (aa != 'X' && aa != 'x') {
                allX = false;
                break;
            }
        }
        if (allX) {
            continue;
        }
        if (std::isnan(gw.n[chainStart + 0].x) && std::isnan(gw.n[chainStart + 1].x) &&
            std::isnan(gw.n[chainStart + 2].x) && std::isnan(gw.n[chainStart + 3].x) &&
            std::isnan(gw.c[chainStart + 0].x) && std::isnan(gw.c[chainStart + 1].x) &&
            std::isnan(gw.c[chainStart + 2].x) && std::isnan(gw.c[chainStart + 3].x)) {
            pulchra.rebuildBackbone(&gw.ca[chainStart], &gw.n[chainStart], &gw.c[chainStart],
                                    &gw.ami[chainStart], chainLen);
        }
        structureTo3Di.structure2states(&gw.ca[chainStart], &gw.n[chainStart], &gw.c[chainStart],
                                        &gw.cb[chainStart], chainLen);
    }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    GemmiWrapper gw;
    const char *buf = reinterpret_cast<const char *>(data);
#if FS_MODE == FS_PDB
    gw.loadFromBuffer(buf, size, "fuzz.pdb", true, GemmiWrapper::Format::Pdb);
#elif FS_MODE == FS_MMCIF
    gw.loadFromBuffer(buf, size, "fuzz.cif", true, GemmiWrapper::Format::Mmcif);
#elif FS_MODE == FS_MMJSON
    gw.loadFromBuffer(buf, size, "fuzz.json", true, GemmiWrapper::Format::Mmjson);
#elif FS_MODE == FS_CHEMCOMP
    gw.loadFromBuffer(buf, size, "fuzz.cif", true, GemmiWrapper::Format::ChemComp);
#elif FS_MODE == FS_FOLDCOMP
    gw.loadFromBuffer(buf, size, "fuzz.fcz", true, GemmiWrapper::Format::Foldcomp);
#elif FS_MODE == FS_ZSTD || FS_MODE == FS_GZIP
    // first byte picks the inner format; the rest is the compressed stream
    if (size < 1) {
        return -1;
    }
    GemmiWrapper::Format format = (data[0] & 1) ? GemmiWrapper::Format::Mmcif : GemmiWrapper::Format::Pdb;
#if FS_MODE == FS_ZSTD
    gw.loadFromBuffer(buf + 1, size - 1, "fuzz.zst", true, format, GemmiWrapper::CompressionFormat::Zstd);
#else
    gw.loadFromBuffer(buf + 1, size - 1, "fuzz.gz", true, format, GemmiWrapper::CompressionFormat::Gzip);
#endif
#elif FS_MODE == FS_CREATEDB
    // explicit PDB/mmCIF format (what the file extension selects in createdb): Format::Detect would
    // also sniff the Foldcomp magic, which fuzz_foldcomp covers, and this target is for the 3Di path
    const bool cif = size >= 5 && memcmp(data, "data_", 5) == 0;
    if (gw.loadFromBuffer(buf, size, cif ? "fuzz.cif" : "fuzz.pdb", false,
                          cif ? GemmiWrapper::Format::Mmcif : GemmiWrapper::Format::Pdb)) {
        runCreatedbPipeline(gw);
    }
#else
#error "unknown FS_MODE"
#endif
    return 0;
}

// Debian port: libjpeg-turbo 2.1 (Debian 13) only has the TurboJPEG 2 API.
// Maps the handful of TurboJPEG 3 calls monologue uses onto it.
#pragma once
#include <turbojpeg.h>
#ifndef TJINIT_DECOMPRESS
enum { TJINIT_DECOMPRESS = 1 };
enum { TJPARAM_JPEGWIDTH, TJPARAM_JPEGHEIGHT, TJPARAM_SUBSAMP };
namespace tj3compat {
struct Header { int w = -1, h = -1, subsamp = -1, colorspace = -1; };
inline Header &header() { thread_local Header s; return s; }
}
inline tjhandle tj3Init(int) { return tjInitDecompress(); }
inline int tj3Destroy(tjhandle h) { return tjDestroy(h); }
inline int tj3DecompressHeader(tjhandle h, const unsigned char *jpeg, size_t size) {
    auto &s = tj3compat::header();
    return tjDecompressHeader3(h, jpeg, (unsigned long)size, &s.w, &s.h, &s.subsamp, &s.colorspace);
}
inline int tj3Get(tjhandle, int param) {
    auto &s = tj3compat::header();
    return param == TJPARAM_JPEGWIDTH ? s.w : param == TJPARAM_JPEGHEIGHT ? s.h : s.subsamp;
}
inline int tj3YUVPlaneWidth(int c, int w, int ss) { return tjPlaneWidth(c, w, ss); }
inline int tj3YUVPlaneHeight(int c, int h, int ss) { return tjPlaneHeight(c, h, ss); }
inline int tj3DecompressToYUVPlanes8(tjhandle h, const unsigned char *jpeg, size_t size,
                                     unsigned char **planes, int *strides) {
    auto &s = tj3compat::header();  // set by the tj3DecompressHeader call just before
    return tjDecompressToYUVPlanes(h, jpeg, (unsigned long)size, planes, s.w, strides, s.h, 0);
}
inline int tj3GetErrorCode(tjhandle h) { return tjGetErrorCode(h); }
#endif

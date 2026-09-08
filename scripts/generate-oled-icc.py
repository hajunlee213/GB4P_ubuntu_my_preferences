#!/usr/bin/env python3
"""
OLED Display Contrast Tuning ICC Profile Generator
Galaxy Book 4 Pro (AMOLED) - VCGT 16-bit Linear Tone Ramp Generator

This script takes a base EDID ICC profile (or standard display ICC) and injects
a 16-bit VCGT (Video Card Gamma Table) tag to lift black points (prevent true black)
and reduce white points (reduce glaring peak white) while preserving 100% color neutrality.
"""

import sys
import os
import glob
import ctypes
import argparse

def find_base_edid():
    # Look for system generated EDID ICC in user share dir
    candidates = glob.glob(os.path.expanduser("~/.local/share/icc/edid-*.icc"))
    if candidates:
        # Return most recently modified or first
        candidates.sort(key=os.path.getmtime, reverse=True)
        return candidates[0]
    # Fallback to standard sRGB if no edid found
    fallback = "/usr/share/color/icc/colord/sRGB.icc"
    if os.path.isfile(fallback):
        return fallback
    return None

def make_profile(src_path, out_path, title, black_offset, white_max):
    if not os.path.isfile(src_path):
        raise FileNotFoundError(f"Source ICC profile not found: {src_path}")

    lcms = ctypes.CDLL('liblcms2.so.2')

    lcms.cmsOpenProfileFromFile.restype = ctypes.c_void_p
    lcms.cmsOpenProfileFromFile.argtypes = [ctypes.c_char_p, ctypes.c_char_p]

    lcms.cmsBuildTabulatedToneCurve16.restype = ctypes.c_void_p
    lcms.cmsBuildTabulatedToneCurve16.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint16)]

    lcms.cmsFreeToneCurve.argtypes = [ctypes.c_void_p]

    lcms.cmsMLUalloc.restype = ctypes.c_void_p
    lcms.cmsMLUalloc.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lcms.cmsMLUsetASCII.restype = ctypes.c_int
    lcms.cmsMLUsetASCII.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
    lcms.cmsMLUfree.argtypes = [ctypes.c_void_p]

    lcms.cmsWriteTag.restype = ctypes.c_int
    lcms.cmsWriteTag.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p]

    lcms.cmsSaveProfileToFile.restype = ctypes.c_int
    lcms.cmsSaveProfileToFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]

    lcms.cmsCloseProfile.restype = ctypes.c_int
    lcms.cmsCloseProfile.argtypes = [ctypes.c_void_p]

    cmsSigVcgtTag = 0x76636774
    cmsSigProfileDescriptionTag = 0x64657363

    hProf = lcms.cmsOpenProfileFromFile(src_path.encode('utf-8'), b'r')
    if not hProf:
        raise RuntimeError(f"Failed to open ICC profile: {src_path}")

    # Set profile description
    mlu = lcms.cmsMLUalloc(None, 1)
    lcms.cmsMLUsetASCII(mlu, b'en', b'US', title.encode('utf-8'))
    lcms.cmsWriteTag(hProf, cmsSigProfileDescriptionTag, mlu)
    lcms.cmsMLUfree(mlu)

    # 1024-entry 16-bit linear ramp
    N = 1024
    vals = (ctypes.c_uint16 * N)()
    for i in range(N):
        x = i / (N - 1)
        y = black_offset + (white_max - black_offset) * x
        vals[i] = int(max(0.0, min(1.0, y)) * 65535.0 + 0.5)

    # Construct identical curves for R, G, B channels
    cR = lcms.cmsBuildTabulatedToneCurve16(None, N, vals)
    cG = lcms.cmsBuildTabulatedToneCurve16(None, N, vals)
    cB = lcms.cmsBuildTabulatedToneCurve16(None, N, vals)
    curves = (ctypes.c_void_p * 3)(cR, cG, cB)

    lcms.cmsWriteTag(hProf, cmsSigVcgtTag, ctypes.byref(curves))
    lcms.cmsFreeToneCurve(cR)
    lcms.cmsFreeToneCurve(cG)
    lcms.cmsFreeToneCurve(cB)

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    res = lcms.cmsSaveProfileToFile(hProf, out_path.encode('utf-8'))
    lcms.cmsCloseProfile(hProf)

    if not res:
        raise RuntimeError(f"Failed to save profile to {out_path}")

    print(f"Generated: {out_path}")
    print(f"  Title: {title}")
    print(f"  Black Lift: {black_offset * 100:.1f}%")
    print(f"  White Max:  {white_max * 100:.1f}%")

def main():
    parser = argparse.ArgumentParser(description="Generate OLED Contrast ICC Profiles")
    parser.add_argument("--src", help="Source base EDID ICC profile path")
    parser.add_argument("--out-dir", default="./configs/icc", help="Output directory")
    parser.add_argument("--black", type=float, help="Custom black offset percentage (e.g. 2.0)")
    parser.add_argument("--white", type=float, help="Custom white max percentage (e.g. 90.0)")
    parser.add_argument("--name", help="Custom output filename")
    parser.add_argument("--title", help="Custom profile title")

    args = parser.parse_args()

    src = args.src or find_base_edid()
    if not src:
        print("Error: Could not locate base EDID ICC profile. Specify with --src <path>.", file=sys.stderr)
        sys.exit(1)

    out_dir = os.path.abspath(args.out_dir)

    if args.black is not None and args.white is not None:
        b = args.black / 100.0
        w = args.white / 100.0
        name = args.name or f"oled_custom_b{args.black:.1f}_w{args.white:.1f}.icc"
        title = args.title or f"OLED Custom (B:{args.black:.1f}% W:{args.white:.1f}%)"
        make_profile(src, os.path.join(out_dir, name), title, b, w)
    else:
        # Default: Generate 2x2 Matrix (High/Medium White x Lifted/Pure Black)
        make_profile(
            src,
            os.path.join(out_dir, "oled_high_contrast.icc"),
            "OLED Eye Care - High Contrast",
            0.020,
            0.900
        )
        make_profile(
            src,
            os.path.join(out_dir, "oled_high_pure_black.icc"),
            "OLED Eye Care - High Pure Black",
            0.000,
            0.900
        )
        make_profile(
            src,
            os.path.join(out_dir, "oled_medium_contrast.icc"),
            "OLED Eye Care - Medium Contrast",
            0.040,
            0.850
        )
        make_profile(
            src,
            os.path.join(out_dir, "oled_medium_pure_black.icc"),
            "OLED Eye Care - Medium Pure Black",
            0.000,
            0.850
        )

if __name__ == "__main__":
    main()

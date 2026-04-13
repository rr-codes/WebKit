list(APPEND ImageDiff_SOURCES
    cg/PlatformImageCG.cpp
)

# FIXME: CoreGraphics.cmake's FindApple.cmake targets don't resolve native macOS framework
# headers -- use -framework directly. https://bugs.webkit.org/show_bug.cgi?id=312069
list(APPEND ImageDiff_LIBRARIES
    "-framework CoreFoundation"
    "-framework CoreGraphics"
    "-framework CoreServices"  # kUTTypePNG
    "-framework CoreText"
    "-framework ImageIO"
)

# kUTTypePNG deprecated in 12.0; our deployment target is 26.2.
list(APPEND ImageDiff_COMPILE_OPTIONS -Wno-deprecated-declarations)

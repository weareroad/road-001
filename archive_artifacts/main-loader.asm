; Standalone fake cassette-loader experiment.

    DEVICE ZXSPECTRUM48

    org $8000

start:
    di
    ld sp,$ff00
    call FakeLoader.Run

.finished:
    ei
    halt
    jr .finished

    INCLUDE "loader.asm"

    SAVESNA "loader-test.sna", start


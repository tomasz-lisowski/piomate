#!/bin/bash
set -o nounset;
set -o pipefail;
set -o errexit;

pioasm -o hex ./example/apa102_1.pio ./example/apa102_1.hex;
./zig-out/bin/piomate disassemble \
    --hex=./example/apa102_1.hex \
    --name=apa102_rgb555 \
    --sideset-count=0 \
    --sideset-pindirs=false \
    --sideset-optional=false \
    2>/dev/null > ./example/tmp.pio;
pioasm -o hex ./example/tmp.pio ./example/tmp.hex;
cmp ./example/apa102_1.hex ./example/tmp.hex;

pioasm -o hex ./example/hub75_0.pio ./example/hub75_0.hex;
./zig-out/bin/piomate disassemble \
    --hex=./example/hub75_0.hex \
    --name=hub75_row \
    --sideset-count=2 \
    --sideset-pindirs=false \
    --sideset-optional=false \
    2>/dev/null > ./example/tmp.pio;
pioasm -o hex ./example/tmp.pio ./example/tmp.hex;
cmp ./example/hub75_0.hex ./example/tmp.hex;

pioasm -o hex ./example/hub75_1.pio ./example/hub75_1.hex;
./zig-out/bin/piomate disassemble \
    --hex=./example/hub75_1.hex \
    --name=hub75_data_rgb888 \
    --sideset-count=1 \
    --sideset-pindirs=false \
    --sideset-optional=false \
    2>/dev/null > ./example/tmp.pio;
pioasm -o hex ./example/tmp.pio ./example/tmp.hex;
cmp ./example/hub75_1.hex ./example/tmp.hex;

pioasm -o hex ./example/i2c_0.pio ./example/i2c_0.hex;
./zig-out/bin/piomate disassemble \
    --hex=./example/i2c_0.hex \
    --name=i2c \
    --sideset-count=1 \
    --sideset-pindirs=true \
    --sideset-optional=true \
    2>/dev/null > ./example/tmp.pio;
pioasm -o hex ./example/tmp.pio ./example/tmp.hex;
cmp ./example/i2c_0.hex ./example/tmp.hex;

pioasm -o hex ./example/onewire_library.pio ./example/onewire_library.hex;
./zig-out/bin/piomate disassemble \
    --hex=./example/onewire_library.hex \
    --name=onewire \
    --sideset-count=1 \
    --sideset-pindirs=true \
    --sideset-optional=false \
    2>/dev/null > ./example/tmp.pio;
pioasm -o hex ./example/tmp.pio ./example/tmp.hex;
cmp ./example/onewire_library.hex ./example/tmp.hex;

pioasm -o hex ./example/quadrature_encoder_substep.pio ./example/quadrature_encoder_substep.hex;
./zig-out/bin/piomate disassemble \
    --hex=./example/quadrature_encoder_substep.hex \
    --name=quadrature_encoder_substep \
    --sideset-count=0 \
    --sideset-pindirs=false \
    --sideset-optional=false \
    2>/dev/null > ./example/tmp.pio;
pioasm -o hex ./example/tmp.pio ./example/tmp.hex;
cmp ./example/quadrature_encoder_substep.hex ./example/tmp.hex;

pioasm -o hex ./example/quadrature_encoder.pio ./example/quadrature_encoder.hex;
./zig-out/bin/piomate disassemble \
    --hex=./example/quadrature_encoder.hex \
    --name=quadrature_encoder \
    --sideset-count=0 \
    --sideset-pindirs=false \
    --sideset-optional=false \
    2>/dev/null > ./example/tmp.pio;
pioasm -o hex ./example/tmp.pio ./example/tmp.hex;
cmp ./example/quadrature_encoder.hex ./example/tmp.hex;

printf "All example files can be disassembled then re-assembled back to the same hex as source.\\n";

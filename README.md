# piomate

## Commands

### Help
Take a look at the output of `piomate help` to see the usage message.

### Disassemble
Take a look at the output of `piomate disassemble --help` to see the usage message.

You can test out the disassembly output using the provided examples:
```bash
piomate disassemble \
    --hex=./example/apa102_1.hex \
    --sideset-count=0 \
    --sideset-pindirs=false \
    --sideset-optional=false
```
You can generate these hex files using `pioasm`.

`pioasm` will prevent you from generating hex for multiple programs at once. When using `piomate disassemble`, you can keep the hex files concatenated and pass the `--start` and `--end` parameters to disassemble each program separately (each with different parameters if needed).

> [!TIP]
> The disassembler provides some debug output by default. If you would only like to see the instructions, redirect `stderr` to `/dev/null` by appending the following to your command: `2>/dev/null`.

## Example
These examples come from [here](https://github.com/raspberrypi/pico-examples/tree/7fe60d6b4027771e45d97f207532c41b1d8c5418/pio).
I minified them by removing new lines and comments.

Before running the bash scripts, please build and install `pioasm` from [here](https://github.com/raspberrypi/pico-sdk/tree/efe2103f9b28458a1615ff096054479743ade236/tools/pioasm).

`test.sh` does the following:
1. Assembles each example.
2. Disassembles the output.
3. Re-assembles the output.
4. Compares the re-assembled output to the original hex.

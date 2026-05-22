# Concerns

- Check whether 100 kHz signal is enough for encoding 53 kHz bandwidth (probably not, we might have to switch to 106 kHz or higher, should not cause issues fir FIR counts)
- With 50 MHz clock we cant use the third harmonic of 33 MHz square, might have to switch to 20 MHz square and 5th harmonic (should still be ok)
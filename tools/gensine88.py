#!/usr/bin/python3

# Generate a sine table for angles 0-255, where 256 represents a full circle (360 degrees). Values are in 8.8 fixed point format (i.e. 1.0 is represented as 256).
import math

def gensine():
    table = []
    for i in range(256):
        angle = (i / 256) * 2 * math.pi # Convert to radians
        sine_value = int(math.sin(angle) * 256) # Scale to 8.8 fixed point
        table.append(sine_value)
    return table

if __name__ == "__main__":
    sine_table = gensine()
    print("uint16_t g_sine_table[256] = {")
    for i in range(0, 256, 8):
        print("    " + ", ".join(f"{sine_table[j]:5d}" for j in range(i, i+8)) + ",")
    print("};")
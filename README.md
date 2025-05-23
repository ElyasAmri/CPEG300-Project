# Project Overview

This project contains several programs and resources related to **8051 Assembly Programming** and **MIDI music generation**. It includes source code for a Snake game using different input methods (buttons and IR remote), as well as music playback functionality.

## Contents

| File Name | Description |
|-----------|-------------|
| `durations_mapping.txt` | Mapping file that defines musical note durations for MIDI playback. |
| `ir.c` | C source code related to Infrared (IR) remote control functionality. |
| `midi.ipynb` | Jupyter Notebook for MIDI file handling and/or generation. |
| `notes_mapping.txt` | Mapping file defining musical notes and corresponding frequencies or codes. |
| `Shop Melody.mid` | MIDI file for the "Shop Melody" (likely intended for playback testing). |
| `snake button grid.asm` | 8051 Assembly source code for Snake game controlled by a button grid. |
| `snake ir.asm` | 8051 Assembly source code for Snake game controlled by an IR remote. |
| `snake no song.asm` | 8051 Assembly source code for Snake game without background music. |
| `Showcase with button grid.mp4` | Video demonstration of the Snake game using button grid input. |
| `Showcase with IR remote.mp4` | Video demonstration of the Snake game using IR remote control. |

## Key Features

- Snake Game Variations:
  - Button Grid Control
  - IR Remote Control
  - With/Without Background Music
- MIDI Music Playback:
  - Note and duration mapping
  - Predefined "Shop Melody" for demo purposes
- Embedded Systems Focus:
  - Designed for microcontroller environments like the 8051
  - Code optimized for low-level control and hardware interaction

## Showcase

### Button Grid Demo
https://github.com/user-attachments/assets/83b6a957-777e-4154-829a-13d0db0e58bb



### IR Remote Demo
https://github.com/user-attachments/assets/f6ece327-e5d3-4c8f-ae40-28e920251dbd


## Requirements

- Assembler/Compiler for 8051 Assembly
- C Compiler (for `ir.c`, if used in microcontroller projects)
- MIDI player (to preview `Shop Melody.mid`)
- Python with Jupyter Notebook installed (for `midi.ipynb`)

## Getting Started

1. Assemble and upload `.asm` files to an 8051-based development board.
2. If using IR control, compile and upload the `ir.c` source.
3. Explore the `midi.ipynb` notebook to understand or modify the MIDI file generation process.
4. Refer to `durations_mapping.txt` and `notes_mapping.txt` if you want to expand or customize music.

## License

This project is provided for educational and personal use. Licensing terms can be adjusted based on your project's needs.

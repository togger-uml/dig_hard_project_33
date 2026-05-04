# Homework 3: VGA Driver — Answers

## Question 1 (3 pts)

The DE10-Lite drives each analog color channel (R, G, B) through a **4-bit resistor ladder**
(four digital FPGA pins per channel), as described in Section 3.8 of the DE10-Lite manual.

Each channel can produce **2⁴ = 16** distinct voltage levels, so the total number of
displayable colors is:

```
16 (red) × 16 (green) × 16 (blue) = 4,096 colors
```

---

## Question 2 (3 pts)

For 640×480 @ 60 Hz the standard VGA timings give the following total pixel counts:

| Dimension  | Active | Front Porch | Sync | Back Porch | **Total** |
|------------|--------|-------------|------|------------|-----------|
| Horizontal | 640    | 16          | 96   | 48         | **800**   |
| Vertical   | 480    | 10          | 2    | 33         | **525**   |

```
Pixel clock = 800 × 525 × 60 Hz ≈ 25.175 MHz
```

The standard VGA pixel clock is **25.175 MHz**.

---

## Question 3 (3 pts)

The diagram below labels each region of the VGA timing waveform.
A "high" color signal means active video; sync pulses are active-low.

```
         ←active→ ←FP→ ←──sync──→ ←──BP──→ ←active→
red/
green/  ▔▔▔▔▔▔▔▔▔▔▔▔|    |         |        |▔▔▔▔▔▔▔▔
blue         (video)                          (video)

hsync   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔|____________|▔▔▔▔▔▔▔▔▔▔▔▔▔▔
                  ↑        ↑            ↑
              H front   H sync       H back
               porch     pulse        porch
```

```
         ←─── active lines ────→ ←VFP→ ←Vsync→ ←──VBP──→ ←── active ──→

vsync   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔|________|▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
                                       ↑        ↑
                                   V sync    V back
                                   pulse      porch
```

**Labels (horizontal):**
- **Horizontal front porch** — the idle period after active video ends and before the hsync pulse begins.
- **Horizontal sync pulse** — the active-low pulse on hsync that marks the end of a scan line.
- **Horizontal back porch** — the idle period after the hsync pulse and before active video begins on the next line.

**Labels (vertical):**
- **Vertical front porch** — the idle period (in lines) after the last active line and before the vsync pulse.
- **Vertical sync pulse** — the active-low pulse on vsync that marks the end of a frame.
- **Vertical back porch** — the idle period (in lines) after the vsync pulse and before the first active line of the next frame.

---

## Question 4 (3 pts)

Standard 640×480 @ 60 Hz VGA timings:

| Parameter                  | Value | Unit   |
|----------------------------|-------|--------|
| Horizontal front porch     | 16    | pixels |
| Horizontal sync pulse width| 96    | pixels |
| Horizontal back porch      | 48    | pixels |
| Vertical front porch       | 10    | lines  |
| Vertical sync pulse width  | 2     | lines  |
| Vertical back porch        | 33    | lines  |

**Sync polarity:** Both hsync and vsync are **negative** (active-low) for 640×480.

---

## Question 5 (3 pts)

Using the totals from Questions 2 and 4:

```
Total pixels per frame  = 800 × 525   = 420,000
Active pixels per frame = 640 × 480   = 307,200
Blanking pixels         = 420,000 − 307,200 = 112,800

Blanking percentage = (112,800 / 420,000) × 100% ≈ 26.86%
```

Approximately **26.86%** of every frame is spent in blanking periods.

---

## Question 6 — Extra Credit (1.5 pts)

**Memory required for a 4-bit framebuffer at 640×480:**

```
640 × 480 × 4 bits = 1,228,800 bits ≈ 1.17 Mbit (≈ 150 KiB)
```

**Double-buffering requirement (two framebuffers):**

```
2 × 1,228,800 bits = 2,457,600 bits ≈ 2.34 Mbit (≈ 300 KiB)
```

**On-chip memory of the MAX 10 (10M50DAF484C7G) on the DE10-Lite:**

The device contains 182 M9K blocks, each 9,216 bits deep, giving:

```
182 × 9,216 = 1,677,312 bits ≈ 1.60 Mbit (≈ 200 KiB)
```

**Conclusion:**

- A single 4-bit framebuffer (≈ 1.17 Mbit) **fits** in on-chip memory (≈ 1.60 Mbit).
- Double-buffering (≈ 2.34 Mbit) **does not fit** — it exceeds the available on-chip
  memory by roughly 0.74 Mbit.

Therefore, **double buffering at 640×480 with 4-bit color cannot be done using only the
on-chip memory** of the MAX 10 FPGA on the DE10-Lite board. External memory (e.g., the
board's SDRAM) would be required.

---

## Question 7 — Extra Credit (1.5 pts)

**1920×1080 @ 60 Hz (CEA-861 / HDMI standard):**

| Parameter                  | Value | Unit   |
|----------------------------|-------|--------|
| Horizontal active          | 1920  | pixels |
| Horizontal front porch     | 88    | pixels |
| Horizontal sync pulse width| 44    | pixels |
| Horizontal back porch      | 148   | pixels |
| **Horizontal total**       | **2200** | **pixels** |
| Vertical active            | 1080  | lines  |
| Vertical front porch       | 4     | lines  |
| Vertical sync pulse width  | 5     | lines  |
| Vertical back porch        | 36    | lines  |
| **Vertical total**         | **1125** | **lines** |

**Pixel clock:**

```
2200 × 1125 × 60 Hz = 148,500,000 Hz = 148.5 MHz
```

**Sync polarity:** Both hsync and vsync are **positive** (active-high) for 1920×1080.

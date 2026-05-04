# sseg_pins.tcl
#
# Extra-credit additions for Homework 5 (EECE.4500/5500)
#
# Q6: sseg_lamps – list of lists of FPGA pins for each seven-segment
#     display on the DE10-Lite.  Each inner list contains seven pin
#     names for segments a, b, c, d, e, f, g in that order.
#
# Q7: set_pins procedure – issues set_location_assignment directives
#     so that Quartus automatically performs pin placement for a
#     record-array signal that connects to the HEX displays.

# ----------------------------------------------------------------
# Q6: FPGA pin table
#
# Source: DE10-Lite QSF (HEX0[0]–HEX5[6] assignments).
# Inner list order: a(0) b(1) c(2) d(3) e(4) f(5) g(6)
# ----------------------------------------------------------------
set sseg_lamps {
    { C14 E15 C15 C16 E16 D17 C17 }
    { C18 D18 E18 B16 A17 A18 B17 }
    { B20 A20 B19 A21 B21 C22 B22 }
    { F21 E22 E21 C19 C20 D19 E17 }
    { F18 E20 E19 J18 H19 F19 F20 }
    { J20 K20 L18 N18 M20 N19 N20 }
}

# ----------------------------------------------------------------
# Q7: set_pins procedure
#
# Usage:
#   set_pins <digits> [<name>]
#
# Parameters:
#   digits – number of hex displays to assign (1 to 6)
#   name   – base name of the signal (default: "hex_digit")
#
# Each pin assignment targets a record-array element:
#   name[i].a, name[i].b, … name[i].g
# ----------------------------------------------------------------
proc set_pins { digits { name "hex_digit" } } {
    global sseg_lamps

    for { set i 0 } { ${i} < ${digits} } { incr i } {
        set j 0
        foreach lamp { a b c d e f g } {
            set location [ lindex [ lindex ${sseg_lamps} ${i} ] ${j} ]
            set_location_assignment PIN_${location} -to ${name}\[${i}\].${lamp}
            incr j
        }
    }
}

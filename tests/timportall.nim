import picostdlib/[adc, clock, gpio, multicore, pwm, stdio, time, watchdog]
import picostdlib/private/linkutils
import std/[unittest, os, macros]
const expected = [
  "hardware_adc",
  "pico_multicore",
  "hardware_pwm",
  "pico_stdlib"
]
var count = 0
for x in ("tests" / LibFileName).lines:
  if x in expected:
    inc count

check count == expected.len
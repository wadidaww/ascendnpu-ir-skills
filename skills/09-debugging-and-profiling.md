# 09 — Debugging & Profiling

## Overview

Effective debugging and profiling are essential for a compiler project like AscendNPU-IR. This guide covers IR-level debugging, pass-level diagnostics, performance analysis, and hardware profiling techniques.

---

## IR-Level Debugging

### Dumping IR at Every Pass
```bash
# Print IR before and after every pass
bishengir-opt --mlir-print-ir-before-all --mlir-print-ir-after-all \
  --pass-pipeline="..." input.mlir 2>&1 | less

# Print IR after a specific pass only
bishengir-opt --mlir-print-ir-after=hfusion-fusion \
  --pass-pipeline="..." input.mlir

# Print IR before a specific pass only
bishengir-opt --mlir-print-ir-before=convert-hfusion-to-hivm \
  --pass-pipeline="..." input.mlir
```

### Using `--verify-each`
```bash
# Verify IR validity after every single pass — catches corruption immediately
bishengir-opt --verify-each --pass-pipeline="..." input.mlir
```
This is the single most effective technique for isolating which pass produces malformed IR. Always use `--verify-each` when debugging unexplained failures.

### Pretty-Printing IR
```bash
# Use generic (verbose) form to see all attributes
bishengir-opt --mlir-print-generic-form input.mlir

# Print op location info (useful for tracing back to source)
bishengir-opt --mlir-print-debuginfo input.mlir
```

---

## Pass-Level Debugging

### Bisecting the Pipeline
When a pipeline produces wrong output, bisect to find the culprit pass:

```bash
# Start with the full pipeline
bishengir-opt --pass-pipeline="A,B,C,D,E,F" input.mlir

# Remove the second half
bishengir-opt --pass-pipeline="A,B,C" input.mlir  # Does this still produce wrong output?

# Binary search until the single offending pass is identified
```

### Debugging Pass Registration
```bash
# List all available passes
bishengir-opt --help 2>&1 | grep '\-\-'

# Print all registered passes with descriptions
bishengir-opt --help-list-hidden 2>&1 | less
```

### Debugging Dialect Conversion Failures
```bash
# Print conversion legality and pattern matching details
bishengir-opt --debug-only=dialect-conversion --pass-pipeline="convert-hfusion-to-hivm" input.mlir

# Print pattern rewrite details
bishengir-opt --debug-only=greedy-rewriter --pass-pipeline="hfusion-fusion" input.mlir
```

The `dialect-conversion` debug output shows:
- Which ops are being processed
- Which patterns matched (or failed to match)
- Why ops were marked illegal

---

## Compiler Assertion Failures

When MLIR/LLVM emits `llvm_unreachable` or assertion failures:

1. **Build with `Debug` mode** (`-DCMAKE_BUILD_TYPE=Debug`) to get full assertion messages and line numbers.
2. **Enable assertions** in release builds: `-DLLVM_ENABLE_ASSERTIONS=ON`.
3. **Run under AddressSanitizer** to catch memory errors:
   ```bash
   cmake -DLLVM_USE_SANITIZER=Address ...
   ```
4. **Use `report_fatal_error` instead of `llvm_unreachable`** in your own code to provide clear diagnostic messages:
   ```cpp
   // BAD: silently terminates with confusing output
   llvm_unreachable("should not reach here");
   
   // GOOD: gives a clear, actionable error message
   op->emitOpError("unexpected op type in MyPass: ") << op->getName();
   return signalPassFailure();
   ```

---

## Performance Profiling

### Step 1 — Identify the Bottleneck
Before profiling, first establish a performance baseline and hypothesis:
- Is the kernel compute-bound (vector/cube utilisation near 100%)?
- Is it memory-bound (DMA bandwidth saturated)?
- Is it synchronisation-bound (many idle cycles waiting on barriers)?

### Step 2 — Profile with Ascend Profiling Tools

CANN provides profiling tools for Ascend hardware:

```bash
# Collect hardware performance counters
msprof --output=./prof_data --application="bishengir-runner kernel.mlir ..."

# View profiling results
msprofdataparser ./prof_data
```

Key metrics to examine:
| Metric | What it reveals |
|---|---|
| AI Core utilisation | Are the vector/cube units busy? |
| DMA bandwidth | Is memory bandwidth the bottleneck? |
| Pipe stall cycles | Are compute and DMA poorly overlapped? |
| L1 hit rate | Is tiling effective? |
| UB reuse factor | Are on-chip buffers reused efficiently? |

### Step 3 — Analyse IR-Level Performance Indicators

Even before hardware profiling, the HIVM IR reveals performance issues:

```
# Red flags in HIVM IR (look for these):
1. DMA ops with small transfer sizes (< 256 bytes) → inefficient DMA
2. Many sequential DMA → compute → DMA without pipeline.begin/end → no overlap
3. Vector ops not aligned to 32-byte boundaries → performance penalty
4. Excessive barrier ops between every DMA and compute → over-synchronisation
5. Large on-chip buffer allocations with low reuse → wasted memory
```

### Step 4 — Tiling Parameter Tuning

Tiling parameters (`tile-sizes`) are the primary knob for performance tuning:

```bash
# Explore tile sizes
bishengir-opt --hfusion-tiling="tile-sizes=16,16" ...
bishengir-opt --hfusion-tiling="tile-sizes=32,32" ...
bishengir-opt --hfusion-tiling="tile-sizes=64,64" ...
```

Rules of thumb:
- Inner tile size should match the vector length (hardware-specific: often 256 or 512 elements for fp16).
- Outer tile size should be large enough that DMA overhead is amortised but small enough to fit in L1.
- For matmul, tile sizes must be multiples of the Cube unit dimensions (typically 16x16 for fp16).

---

## Common Performance Bugs

| Bug | Symptom | Fix |
|---|---|---|
| No ping-pong pipeline | DMA and compute do not overlap; low AI Core utilisation | Wrap tiled loop with `hivm.pipeline.begin {depth = 2}` |
| Over-synchronisation | Many barrier ops; AI Core idle most of the time | Merge barriers; use the minimal set of barriers required |
| Tile size too small | Very high DMA overhead; low compute-to-memory ratio | Increase tile size until DMA is < 10% of total cycles |
| Tile size too large | On-chip buffer overflow at compile time or silent UB corruption | Reduce tile size to fit within on-chip memory budget |
| Unnecessary type casting | Extra conversion ops consuming UB bandwidth | Check type promotion policy; avoid converting if not necessary |

---

## Debug vs Release Builds

| Aspect | Debug | RelWithDebInfo | Release |
|---|---|---|---|
| Assertions | ON | ON | OFF |
| Debug symbols | Full | Full | None |
| Optimisation | -O0 | -O2 | -O3 |
| Best for | Correctness debugging | Normal development | Performance benchmarking |

Always benchmark performance in `Release` or `RelWithDebInfo` mode. `Debug` builds can be 10–50× slower.

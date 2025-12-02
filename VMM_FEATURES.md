# Virtual Memory Manager (VMM) - Feature Overview

## Overview
j3kOS now includes a comprehensive Virtual Memory Manager with hot/cold page tracking and RLE compression for memory optimization.

## Core Features

### 1. **Hardware Paging Support**
- Two-level x86 paging (Page Directory + Page Tables)
- 4KB page granularity
- Page Directory at 0x200000
- Page Tables at 0x201000
- Supports up to 16MB physical memory (4096 pages)

### 2. **Memory Protection**
- User/Supervisor mode separation
- Read/Write permissions per page
- Present/Not-present tracking
- Page fault handling (INT 14)

### 3. **Page Frame Allocator**
- Bitmap-based physical page tracking
- First-fit allocation algorithm
- Tracks 4096 physical pages (16MB)
- Efficient allocation/deallocation

### 4. **Virtual Memory Operations**
- `vmm_map_page()` - Map virtual to physical address
- `vmm_unmap_page()` - Unmap and free page
- `vmm_alloc()` - Allocate virtual memory region
- `vmm_free()` - Free virtual memory region
- `vmm_get_physical()` - Translate virtual to physical address

### 5. **Hot/Cold Page Tracking**
- Automatic page access monitoring
- Hot threshold: 10 accesses
- Cold threshold: 50 timer ticks without access
- Compression threshold: 100 ticks cold

### 6. **RLE Compression for Cold Pages**
- Automatic compression of cold pages
- Simple Run-Length Encoding (RLE)
- Only compresses if >25% size reduction achieved
- Transparent decompression on access
- Saves memory by compressing unused pages

### 7. **Page States**
- `FREE` - Unallocated page
- `ALLOCATED` - In use, not accessed recently
- `HOT` - Frequently accessed (≥10 accesses)
- `COLD` - Rarely accessed (≥50 ticks idle)
- `COMPRESSED` - Cold page compressed with RLE
- `SWAPPED` - Saved to disk (framework in place)

### 8. **Timer Integration**
- VMM page aging runs every 10 timer ticks
- Automatic hot→cold→compressed transitions
- Non-intrusive background compression

## Statistics Tracked
- Pages allocated/freed
- Page faults handled
- TLB flushes
- Hot/Cold/Compressed page counts
- Compression/Decompression operations

## Shell Commands

### Memory Management
- `:vmm` - Display VMM statistics
- `:vmalloc` - Allocate 16KB virtual memory
- `:vmap` - Map a page at 0x800000
- `:malloc` - Test heap allocator

### Compression Testing
- `:compress` - Test page compression (creates page with pattern, marks cold, compresses)
- `:decompress` - Test decompression (accesses compressed page, triggers decompression)

## Memory Layout

```
0x00000000 - 0x000FFFFF : Low memory (1MB)
  0x00000000 - 0x000004FF : Real mode IVT + BIOS data
  0x00007C00 - 0x00007DFF : Boot sector
  0x00010000 - 0x0001FFFF : Kernel (69KB actual)
  0x00090000 - 0x0009FFFF : Stack (64KB, grows down)
  0x000A0000 - 0x000BFFFF : VGA memory

0x00100000 - 0x001FFFFF : Heap (1MB - malloc region)
0x00200000 - 0x00200FFF : Page Directory (4KB)
0x00201000 - 0x002FFFFF : Page Tables (up to 1MB)
0x00300000 - 0x00300FFF : Compression temp buffer (4KB)
0x00400000+             : Virtual memory allocations
```

## Technical Details

### Page Directory Entry (PDE) Format
```
Bits 31-12: Page Table Physical Address
Bit  11-9:  Available for OS use
Bit  8:     Global (G)
Bit  7:     Page Size (0 = 4KB)
Bit  6:     Reserved
Bit  5:     Accessed (A)
Bit  4:     Cache Disable (PCD)
Bit  3:     Write-Through (PWT)
Bit  2:     User/Supervisor (U/S)
Bit  1:     Read/Write (R/W)
Bit  0:     Present (P)
```

### Page Table Entry (PTE) Format
```
Bits 31-12: Physical Page Address
Bit  11-9:  Available (we use for COW, SWAPPED flags)
Bit  8:     Global (G)
Bit  7:     Reserved
Bit  6:     Dirty (D)
Bit  5:     Accessed (A)
Bit  4:     Cache Disable (PCD)
Bit  3:     Write-Through (PWT)
Bit  2:     User/Supervisor (U/S)
Bit  1:     Read/Write (R/W)
Bit  0:     Present (P)
```

### Page Tracking Entry (16 bytes per page)
```
Offset 0:  State (1 byte) - FREE/ALLOCATED/HOT/COLD/COMPRESSED/SWAPPED
Offset 1:  Access count (1 byte)
Offset 2:  Ticks since last access (2 bytes)
Offset 4:  Physical address (4 bytes)
Offset 8:  Compressed size (4 bytes) - only used if COMPRESSED
Offset 12: Flags (4 bytes) - reserved for future use
```

## RLE Compression Algorithm

The VMM uses a simple but effective Run-Length Encoding:

1. **Compression**: Scans page byte-by-byte, encoding runs as [count][byte]
   - Only compresses if result is <75% of original size
   - Works well for pages with repeated patterns (zeros, stack frames, etc.)

2. **Decompression**: Reads [count][byte] pairs and expands them
   - Triggered automatically on page access
   - Page marked as HOT after decompression
   - Transparent to the accessing code

## Future Enhancements

- [ ] Copy-on-Write (COW) support
- [ ] Demand paging from disk
- [ ] Swap space integration
- [ ] Better compression algorithms (LZ77, etc.)
- [ ] Memory mapped files
- [ ] Shared memory regions
- [ ] TLB shootdown for multiprocessor support

## Testing

Build and run:
```batch
.\build.bat
.\test.bat
```

Test commands in order:
```
:vmm          # Show initial stats (should be 0s)
:compress     # Create and compress a page
:vmm          # See compressed page stats
:decompress   # Access compressed page
:vmm          # See decompression stats
```

## Performance Notes

- Page aging runs every 10 timer ticks (~55ms at 18.2 Hz)
- Compression is non-blocking and happens in background
- Decompression on first access incurs ~1-2ms penalty
- TLB invalidation uses `invlpg` for single pages
- Bitmap allocation is O(n) but fast for 4096 pages

## Integration Points

1. **Timer IRQ (IRQ0)**: Calls `vmm_page_timer_tick()` every 10 ticks
2. **Page Faults (INT 14)**: Handled by `vmm_page_fault_handler_enhanced()`
3. **Memory Access**: Should call `vmm_page_accessed()` for tracking (optional)
4. **Initialization**: Called from kernel startup via `vmm_init()`

---
**Created**: December 2, 2025
**Author**: Jortboy3k (@jortboy3k)
**Version**: j3kOS v1.0 with VMM

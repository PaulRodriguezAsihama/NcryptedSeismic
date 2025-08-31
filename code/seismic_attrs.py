#!/usr/bin/env python3
"""
Seismic Attributes Calculator for 3D SEG-Y Cubes

This script processes 3D seismic data in SEG-Y format to compute coherence and
curvature attributes. It supports memory-mapped I/O, flexible normalization,
and subset extraction for efficient processing of large datasets.

Author: NCrypted Seismic
Version: 1.0.0
"""

import argparse
import json
import time
import warnings
from pathlib import Path
from typing import Tuple, Dict, Any, Optional
import sys

import numpy as np
import segyio
from scipy import ndimage
from scipy.ndimage import gaussian_filter, uniform_filter
from tqdm import tqdm

# Suppress warnings for cleaner output
warnings.filterwarnings('ignore', category=RuntimeWarning)


def parse_range(range_str: str) -> Tuple[int, int]:
    """Parse range string 'start:end' to tuple."""
    if ':' not in range_str:
        raise ValueError(f"Invalid range format: {range_str}. Use 'start:end'")
    start, end = map(int, range_str.split(':'))
    if start >= end:
        raise ValueError(
            f"Invalid range: start ({start}) must be < end ({end})")
    return start, end


def parse_patch(patch_str: str) -> Tuple[int, int, int]:
    """Parse patch string 'py,px,pz' to tuple."""
    try:
        py, px, pz = map(int, patch_str.split(','))
        # Ensure odd values
        py = py if py % 2 == 1 else py + 1
        px = px if px % 2 == 1 else px + 1
        pz = pz if pz % 2 == 1 else pz + 1
        if any(p < 3 for p in (py, px, pz)):
            raise ValueError("Patch sizes must be >= 3")
        return py, px, pz
    except Exception as e:
        raise ValueError(
            f"Invalid patch format: {patch_str}. Use 'py,px,pz'") from e


def load_segy_cube(filepath: Path,
                   iline_range: Optional[Tuple[int, int]] = None,
                   xline_range: Optional[Tuple[int, int]] = None,
                   z_range: Optional[Tuple[int, int]] = None,
                   swap_axes: Optional[str] = None,
                   verbose: bool = False) -> Tuple[np.ndarray, Dict[str, Any]]:
    """
    Load SEG-Y cube with optional cropping and axis swapping.

    Returns:
        data: numpy array of shape (n_ilines, n_xlines, n_samples)
        metadata: dictionary with cube information
    """
    if verbose:
        print(f"Loading SEG-Y file: {filepath}")

    with segyio.open(filepath, 'r', strict=False) as f:
        # Get cube dimensions
        n_ilines = len(f.ilines)
        n_xlines = len(f.xlines)
        n_samples = len(f.samples)

        # Determine crop indices
        il_start = iline_range[0] if iline_range else 0
        il_end = iline_range[1] if iline_range else n_ilines
        xl_start = xline_range[0] if xline_range else 0
        xl_end = xline_range[1] if xline_range else n_xlines
        z_start = z_range[0] if z_range else 0
        z_end = z_range[1] if z_range else n_samples

        # Validate ranges
        if il_end > n_ilines or xl_end > n_xlines or z_end > n_samples:
            raise ValueError(f"Crop ranges exceed cube dimensions: "
                           f"({n_ilines}, {n_xlines}, {n_samples})")

        # Load cube efficiently using segyio
        if verbose:
            print("Reading cube data...")

        # Use segyio.tools.cube for full cube, then crop
        try:
            cube = segyio.tools.cube(f)
            # Crop the cube
            data = cube[il_start:il_end, xl_start:xl_end,
                z_start:z_end].astype(np.float32)
        except MemoryError:
            # Fall back to trace-by-trace reading
            if verbose:
                print("Memory error: falling back to trace-by-trace reading...")
            data = np.zeros((il_end - il_start, xl_end - xl_start, z_end - z_start),
                           dtype=np.float32)
            for i, il in enumerate(tqdm(range(il_start, il_end), desc="Loading traces")):
                for j, xl in enumerate(range(xl_start, xl_end)):
                    trace_idx = il * n_xlines + xl
                    data[i, j, :] = f.trace[trace_idx][z_start:z_end]

        metadata = {
            'original_shape': (n_ilines, n_xlines, n_samples),
            'cropped_shape': data.shape,
            'iline_range': (il_start, il_end),
            'xline_range': (xl_start, xl_end),
            'z_range': (z_start, z_end),
            'sample_interval': f.bin[segyio.BinField.Interval],
            'format': f.format
        }

    # Apply axis swapping if requested
    if swap_axes:
        perm = list(map(int, swap_axes.split(',')))
        if len(perm) != 3 or set(perm) != {0, 1, 2}:
            raise ValueError(f"Invalid axis permutation: {swap_axes}")
        data = np.transpose(data, perm)
        metadata['axes_permutation'] = perm
        if verbose:
            print(f"Applied axis permutation: {perm}")

    if verbose:
        print(f"Loaded data shape: {data.shape}, dtype: {data.dtype}")

    return data, metadata


def normalize_volume(data: np.ndarray,
                    mode: str = 'both',
                    z_window: int = 9,
                    eps: float = 1e-6,
                    verbose: bool = False) -> np.ndarray:
    """
    Normalize seismic volume using specified mode.

    Modes:
        - 'none': No normalization
        - 'trace': Z-score normalization per trace
        - 'z': Z-score normalization per z-window
        - 'both': Apply trace then z normalization
    """
    if mode == 'none':
        return data

    result = data.copy()

    if mode in ['trace', 'both']:
        if verbose:
            print("Applying trace normalization...")
        # Normalize each trace independently
        for i in tqdm(range(result.shape[0]), desc="Trace norm", disable=not verbose):
            for j in range(result.shape[1]):
                trace = result[i, j, :]
                mean = np.mean(trace)
                std = np.std(trace) + eps
                result[i, j, :] = (trace - mean) / std

    if mode in ['z', 'both']:
        if verbose:
            print(f"Applying z-window normalization (window={z_window})...")

        # Ensure z_window is odd
        if z_window % 2 == 0:
            z_window += 1
            if verbose:
                print(f"Adjusted z_window to {z_window} (must be odd)")

        # Compute local statistics using uniform filter
        # Pad in z-direction to handle boundaries
        pad_z = z_window // 2
        padded = np.pad(
            result, ((0, 0), (0, 0), (pad_z, pad_z)), mode='reflect')

        # Compute local mean and variance efficiently
        local_mean = uniform_filter(
            padded, size=(1, 1, z_window), mode='nearest')
        local_mean = local_mean[:, :, pad_z:-pad_z]

        padded_sq = padded ** 2
        local_mean_sq = uniform_filter(
            padded_sq, size=(1, 1, z_window), mode='nearest')
        local_mean_sq = local_mean_sq[:, :, pad_z:-pad_z]

        local_var = local_mean_sq - local_mean ** 2
        local_std = np.sqrt(np.maximum(local_var, 0)) + eps

        result = (result - local_mean) / local_std

    return result


def coherence_3d(data: np.ndarray,
                patch_size: Tuple[int, int, int] = (5, 5, 9),
                verbose: bool = False) -> np.ndarray:
    """
    Compute 3D coherence using semblance-like measure.

    Coherence = (sum(W))^2 / (N * sum(W^2))
    where W are values in the local window and N is the number of samples.
    """
    if verbose:
        print(f"Computing 3D coherence with patch size {patch_size}...")

    py, px, pz = patch_size

    # Compute sum of values and sum of squared values using uniform filter
    sum_vals = uniform_filter(data, size=(py, px, pz), mode='nearest')
    sum_sq_vals = uniform_filter(data ** 2, size=(py, px, pz), mode='nearest')

    # Number of samples in patch
    n_samples = py * px * pz

    # Compute coherence with epsilon to avoid division by zero
    eps = 1e-6
    coherence = (sum_vals ** 2) / (n_samples

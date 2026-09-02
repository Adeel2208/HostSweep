"""
HostSweep - Modular dual-pass workflow for reducing human read content in
Illumina metagenomic data.

Combines minimap2 and Bowtie2 alignment against T2T-CHM13v2.0 to produce three
tiered outputs: assembly-grade paired-end, profiling-grade single-end, and a
high-stringency complexity- and length-filtered single-end set.

HostSweep reduces detectable human sequence under the conditions described in
the repository README; it does not certify the absence of human material.

Authors: Adeel Mukhtar, Umair Tariq, Awais Abdul Khaliq
Version: 1.0.0
License: MIT
"""

__version__ = "1.0.0"
__author__ = "Adeel Mukhtar, Umair Tariq, Awais Abdul Khaliq"
__email__ = "umair.tariq@bcu.ac.uk"

from .database import DatabaseManager
from .pipeline import HostSweep
from .cli import main

__all__ = ['DatabaseManager', 'HostSweep', 'main', '__version__']

"""
HostSweep - Modular dual-pass pipeline for human DNA decontamination in Illumina metagenomic data
Combines minimap2 and Bowtie2 alignment against T2T-CHM13v2.0 with tiered outputs

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

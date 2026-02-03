"""
DecontaMiner - Advanced Human DNA Decontamination Pipeline
Enhanced modular version for Illumina metagenomic data

Author: Adeel
Version: 1.0.0
License: MIT
"""

__version__ = "1.0.0"
__author__ = "Adeel"
__email__ = "contact@decontaminer.org"

from .database import DatabaseManager
from .pipeline import DecontaMiner
from .cli import main

__all__ = ['DatabaseManager', 'DecontaMiner', 'main', '__version__']

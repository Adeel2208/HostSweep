#!/usr/bin/env python3
from setuptools import setup, find_packages
from pathlib import Path

readme_file = Path(__file__).parent / "README.md"
long_description = readme_file.read_text() if readme_file.exists() else ""

setup(
    name='hostsweep',
    version='1.0.0',
    description='Modular dual-pass pipeline for human DNA decontamination in Illumina metagenomic data',
    long_description=long_description,
    long_description_content_type='text/markdown',
    author='Adeel Mukhtar, Umair Tariq, Awais Abdul Khaliq',
    author_email='umair.tariq@bcu.ac.uk',
    url='https://github.com/Adeel2208/HostSweep',
    license='MIT',

    packages=find_packages(),

    entry_points={
        'console_scripts': [
            'hostsweep=hostsweep.cli:main',
        ],
    },

    python_requires='>=3.9',
    include_package_data=True,
)

#!/usr/bin/env python3
from setuptools import setup, find_packages
from pathlib import Path

readme_file = Path(__file__).parent / "README.md"
long_description = readme_file.read_text() if readme_file.exists() else ""

setup(
    name='decontaminer',
    version='1.0.0',
    description='Advanced Human DNA Decontamination Pipeline',
    long_description=long_description,
    long_description_content_type='text/markdown',
    author='Adeel',
    url='https://github.com/Adeel2208/Host_Buster',
    license='MIT',

    packages=find_packages(),

    entry_points={
        'console_scripts': [
            'decontaminer=decontaminer.cli:main',
        ],
    },

    python_requires='>=3.9',
    include_package_data=True,
)

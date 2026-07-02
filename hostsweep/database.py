"""Database Manager for reference genome indices"""
import os
import json
import gzip
import shutil
import subprocess
import urllib.request
import multiprocessing
from pathlib import Path
from datetime import datetime


class DatabaseManager:
    """Manage reference genome databases and indices"""

    # T2T-CHM13v2.0 full genome URL
    T2T_URL = ("https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/"
               "GCF_009914755.1_T2T-CHM13v2.0/"
               "GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz")

    def __init__(self, env_path=None):
        self.env_path = env_path or self.get_conda_env_path()
        self.db_base = Path(self.env_path) / "share" / "hostsweep" / "databases"
        self.db_base.mkdir(parents=True, exist_ok=True)

        self.standard_path = self.db_base / "standard"
        self.custom_path = self.db_base / "custom"
        self.custom_path.mkdir(parents=True, exist_ok=True)
        self.version_file = self.db_base / "db_version.json"

    @staticmethod
    def get_conda_env_path():
        if 'CONDA_PREFIX' in os.environ:
            return os.environ['CONDA_PREFIX']
        else:
            return str(Path.home() / ".hostsweep")

    def get_db_version(self):
        if self.version_file.exists():
            with open(self.version_file, 'r') as f:
                return json.load(f)
        return {}

    def save_db_version(self, index_name, info):
        from . import __version__
        versions = self.get_db_version()
        versions[index_name] = {
            **info,
            "hostsweep_version": __version__,
            "created_at": datetime.now().isoformat()
        }
        with open(self.version_file, 'w') as f:
            json.dump(versions, f, indent=2)

    def list_indices(self):
        """List all available index databases"""
        indices = []

        # Check standard
        if self.standard_path.exists():
            mmi = self.standard_path / "human.mmi"
            bt2 = self.standard_path / "human_bt2.1.bt2"
            if mmi.exists() or bt2.exists():
                indices.append({
                    "name": "standard",
                    "path": str(self.standard_path),
                    "minimap2": mmi.exists(),
                    "bowtie2": bt2.exists(),
                    "reference": "T2T-CHM13v2.0"
                })

        # Check custom indices
        if self.custom_path.exists():
            for item in self.custom_path.iterdir():
                if item.is_dir():
                    indices.append({
                        "name": f"custom/{item.name}",
                        "path": str(item),
                        "minimap2": (item / "index.mmi").exists(),
                        "bowtie2": (item / "index_bt2.1.bt2").exists(),
                        "reference": "custom"
                    })

        return indices

    def get_index_paths(self, index_name="standard"):
        """Get minimap2 and bowtie2 index paths for a given index"""
        if index_name == "standard":
            base = self.standard_path
            mmi = base / "human.mmi"
            bt2 = base / "human_bt2"
        else:
            base = self.custom_path / index_name
            mmi = base / "index.mmi"
            bt2 = base / "index_bt2"

        if not base.exists():
            raise FileNotFoundError(
                f"Index '{index_name}' not found. Run: hostsweep --build"
            )

        return {
            "minimap2": str(mmi),
            "bowtie2": str(bt2),
            "base": str(base)
        }

    def download_reference(self, output_path, logger=None):
        """Download T2T-CHM13v2.0 reference genome"""
        gz_path = str(output_path) + ".gz"

        if logger:
            logger.info(f"Downloading T2T-CHM13v2.0 reference to {gz_path}")
            logger.info(f"URL: {self.T2T_URL}")

        try:
            urllib.request.urlretrieve(self.T2T_URL, gz_path)
        except Exception as e:
            raise RuntimeError(f"Download failed: {e}")

        # Decompress
        if logger:
            logger.info("Decompressing reference...")
        with gzip.open(gz_path, 'rb') as f_in:
            with open(output_path, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)

        os.remove(gz_path)
        if logger:
            logger.info(f"Reference ready: {output_path}")
        return output_path

    def build_standard_index(self, threads=4, logger=None):
        """Build the standard T2T-CHM13v2.0 index (download + minimap2 + bowtie2)"""
        self.standard_path.mkdir(parents=True, exist_ok=True)
        ref_fasta = self.standard_path / "human_T2T.fasta"
        mmi_path = self.standard_path / "human.mmi"
        bt2_prefix = self.standard_path / "human_bt2"

        # Download if needed
        if not ref_fasta.exists():
            self.download_reference(str(ref_fasta), logger)

        # Build minimap2 index
        if not mmi_path.exists():
            if logger:
                logger.info("Building minimap2 index (this takes a few minutes)...")
            subprocess.run(
                f"minimap2 -x sr -d {mmi_path} {ref_fasta}",
                shell=True, check=True
            )

        # Build bowtie2 index
        bt2_check = Path(str(bt2_prefix) + ".1.bt2")
        if not bt2_check.exists():
            if logger:
                logger.info("Building bowtie2 index (this takes 20-30 minutes)...")
            subprocess.run(
                f"bowtie2-build --threads {threads} {ref_fasta} {bt2_prefix}",
                shell=True, check=True
            )

        # Save version info
        self.save_db_version("standard", {
            "reference": "T2T-CHM13v2.0",
            "source": self.T2T_URL,
            "minimap2_index": str(mmi_path),
            "bowtie2_prefix": str(bt2_prefix)
        })

        if logger:
            logger.info("Standard index build complete.")
        return self.get_index_paths("standard")

    def build_custom_index(self, index_name, ref_fasta, threads=4, logger=None):
        """Build a custom index from user-provided FASTA"""
        custom_dir = self.custom_path / index_name
        custom_dir.mkdir(parents=True, exist_ok=True)

        mmi_path = custom_dir / "index.mmi"
        bt2_prefix = custom_dir / "index_bt2"

        if logger:
            logger.info(f"Building custom index '{index_name}' from {ref_fasta}")

        # minimap2
        subprocess.run(
            f"minimap2 -x sr -d {mmi_path} {ref_fasta}",
            shell=True, check=True
        )

        # bowtie2
        subprocess.run(
            f"bowtie2-build --threads {threads} {ref_fasta} {bt2_prefix}",
            shell=True, check=True
        )

        # Save version
        self.save_db_version(index_name, {
            "reference": "custom",
            "source_fasta": ref_fasta,
            "minimap2_index": str(mmi_path),
            "bowtie2_prefix": str(bt2_prefix)
        })

        if logger:
            logger.info(f"Custom index '{index_name}' build complete.")
        return self.get_index_paths(index_name)

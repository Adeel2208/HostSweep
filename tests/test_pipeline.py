"""Basic smoke tests for DecontaMiner modules"""
import sys
import os
import pytest

# Make sure the package is importable from repo root
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))


def test_version_import():
    """Package version is accessible"""
    from decontaminer import __version__
    assert __version__ == "1.0.0"


def test_stats_collector():
    """StatsCollector logs steps and finalises correctly"""
    from decontaminer.stats import StatsCollector

    sc = StatsCollector("test_sample", "1.0.0")
    result = sc.log_step("step1_fastp_qc", 1000, 950)

    assert result['input']     == 1000
    assert result['output']    == 950
    assert result['filtered']  == 50
    assert abs(result['retention'] - 95.0) < 0.01

    final = sc.finalize(120.0)
    assert final['total_runtime_seconds'] == 120.0
    assert final['total_runtime_minutes'] == 2.0
    assert 'step1_fastp_qc' in final['steps']


def test_count_reads_missing_file():
    """count_reads returns 0 for non-existent file"""
    from decontaminer.utils import count_reads
    assert count_reads("/nonexistent/path/file.fastq.gz") == 0


def test_database_manager_init():
    """DatabaseManager initialises without crashing"""
    from decontaminer.database import DatabaseManager
    db = DatabaseManager(env_path="/tmp/test_decontaminer_env")
    assert db.db_base.exists()
    # No indices yet
    assert db.list_indices() == []


def test_database_manager_version_roundtrip(tmp_path):
    """Version file write + read round-trips correctly"""
    from decontaminer.database import DatabaseManager
    db = DatabaseManager(env_path=str(tmp_path))
    db.save_db_version("standard", {"reference": "T2T-CHM13v2.0"})

    versions = db.get_db_version()
    assert "standard" in versions
    assert versions["standard"]["reference"] == "T2T-CHM13v2.0"
    assert "decontaminer_version" in versions["standard"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

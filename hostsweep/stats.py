"""Statistics and reporting module"""
import json
from datetime import datetime


class StatsCollector:
    """Collect and report pipeline statistics"""

    def __init__(self, sample_name, pipeline_version):
        self.stats = {
            "sample_name": sample_name,
            "pipeline_version": pipeline_version,
            "pipeline_start": datetime.now().isoformat(),
            "steps": {}
        }

    def log_step(self, step_name, input_count, output_count, **kwargs):
        """Log statistics for a pipeline step"""
        retention = (output_count / input_count * 100) if input_count > 0 else 0
        filtered = input_count - output_count

        self.stats['steps'][step_name] = {
            "input_reads": input_count,
            "output_reads": output_count,
            "filtered_reads": filtered,
            "retention_percent": round(retention, 2),
            "timestamp": datetime.now().isoformat(),
            **kwargs
        }

        return {
            'input': input_count,
            'output': output_count,
            'filtered': filtered,
            'retention': retention
        }

    def finalize(self, total_runtime):
        """Finalize statistics"""
        self.stats['pipeline_end'] = datetime.now().isoformat()
        self.stats['total_runtime_seconds'] = round(total_runtime, 2)
        self.stats['total_runtime_minutes'] = round(total_runtime / 60, 2)
        return self.stats

    def save(self, output_path):
        """Save stats to JSON file"""
        with open(output_path, 'w') as f:
            json.dump(self.stats, f, indent=2)
        return output_path

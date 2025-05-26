#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Custom Ansible filter plugins for LIONS Infrastructure.

These filters provide additional functionality for Ansible playbooks
used in the LIONS Infrastructure deployment.

Author: LIONS Infrastructure Team
Date: 2025-05-24
Version: 1.2.0
"""

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import re
import json
import yaml
import base64
import hashlib
import ipaddress
import os
import random
import string
from datetime import datetime


class FilterModule(object):
    """Custom Ansible filters for LIONS Infrastructure."""

    def filters(self):
        """Return the filter mapping."""
        return {
            'to_yaml': self.to_yaml,
            'from_yaml': self.from_yaml,
            'to_json': self.to_json,
            'from_json': self.from_json,
            'b64encode': self.b64encode,
            'b64decode': self.b64decode,
            'hash_password': self.hash_password,
            'parse_version': self.parse_version,
            'ip_in_network': self.ip_in_network,
            'format_timestamp': self.format_timestamp,
            'extract_domain': self.extract_domain,
            'k8s_resource_name': self.k8s_resource_name,
            'merge_configs': self.merge_configs,
            'filter_pods': self.filter_pods,
            'generate_password': self.generate_password,
        }

    def to_yaml(self, data, indent=2):
        """Convert data to YAML format."""
        return yaml.dump(data, default_flow_style=False, indent=indent)

    def from_yaml(self, yaml_str):
        """Parse YAML string into data structure."""
        return yaml.safe_load(yaml_str)

    def to_json(self, data, pretty=False):
        """Convert data to JSON format."""
        if pretty:
            return json.dumps(data, indent=2, sort_keys=True)
        return json.dumps(data)

    def from_json(self, json_str):
        """Parse JSON string into data structure."""
        return json.loads(json_str)

    def b64encode(self, data):
        """Encode data as base64."""
        if isinstance(data, str):
            data = data.encode('utf-8')
        return base64.b64encode(data).decode('utf-8')

    def b64decode(self, data):
        """Decode base64 data."""
        if isinstance(data, str):
            data = data.encode('utf-8')
        return base64.b64decode(data).decode('utf-8')

    def hash_password(self, password, salt=None, algorithm='sha256'):
        """Hash a password using the specified algorithm."""
        if salt is None:
            salt = hashlib.sha256(datetime.now().isoformat().encode()).hexdigest()[:8]

        hash_obj = hashlib.new(algorithm)
        hash_obj.update((password + salt).encode('utf-8'))
        return f"{algorithm}${salt}${hash_obj.hexdigest()}"

    def parse_version(self, version_str):
        """Parse a version string into a comparable tuple."""
        if not version_str:
            return (0, 0, 0)

        # Extract version components
        match = re.search(r'(\d+)\.(\d+)\.(\d+)', version_str)
        if match:
            return tuple(int(x) for x in match.groups())

        # Handle version strings with only major.minor
        match = re.search(r'(\d+)\.(\d+)', version_str)
        if match:
            return (int(match.group(1)), int(match.group(2)), 0)

        # Handle version strings with only major
        match = re.search(r'(\d+)', version_str)
        if match:
            return (int(match.group(1)), 0, 0)

        return (0, 0, 0)

    def ip_in_network(self, ip, network):
        """Check if an IP address is within a network range."""
        try:
            return ipaddress.ip_address(ip) in ipaddress.ip_network(network)
        except ValueError:
            return False

    def format_timestamp(self, timestamp=None, format_str="%Y-%m-%d %H:%M:%S"):
        """Format a timestamp according to the specified format."""
        if timestamp is None:
            timestamp = datetime.now()
        elif isinstance(timestamp, (int, float)):
            timestamp = datetime.fromtimestamp(timestamp)
        elif isinstance(timestamp, str):
            try:
                timestamp = datetime.fromisoformat(timestamp)
            except ValueError:
                try:
                    timestamp = datetime.fromtimestamp(float(timestamp))
                except ValueError:
                    return timestamp

        return timestamp.strftime(format_str)

    def extract_domain(self, url):
        """Extract the domain from a URL."""
        if not url:
            return ""

        match = re.search(r'https?://([^/]+)', url)
        if match:
            return match.group(1)

        return url

    def k8s_resource_name(self, name):
        """Convert a string to a valid Kubernetes resource name."""
        # Replace invalid characters with dashes
        name = re.sub(r'[^a-z0-9-]', '-', name.lower())
        # Remove leading and trailing dashes
        name = name.strip('-')
        # Replace multiple consecutive dashes with a single dash
        name = re.sub(r'-+', '-', name)
        # Ensure name is not longer than 63 characters
        return name[:63]

    def merge_configs(self, base_config, override_config):
        """Recursively merge two configuration dictionaries."""
        result = base_config.copy()

        for key, value in override_config.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = self.merge_configs(result[key], value)
            else:
                result[key] = value

        return result

    def filter_pods(self, pods, namespace=None, label_selector=None, status=None):
        """Filter a list of pods based on namespace, labels, and status."""
        result = []

        for pod in pods:
            # Filter by namespace
            if namespace and pod.get('metadata', {}).get('namespace') != namespace:
                continue

            # Filter by label selector
            if label_selector:
                pod_labels = pod.get('metadata', {}).get('labels', {})
                match = True
                for key, value in label_selector.items():
                    if pod_labels.get(key) != value:
                        match = False
                        break
                if not match:
                    continue

            # Filter by status
            if status and pod.get('status', {}).get('phase') != status:
                continue

            result.append(pod)

        return result

    def generate_password(self, length=16, include_special=True):
        """Generate a random password of the specified length."""
        import random
        import string

        chars = string.ascii_letters + string.digits
        if include_special:
            chars += '!@#$%^&*()-_=+[]{}|;:,.<>?'

        return ''.join(random.choice(chars) for _ in range(length))

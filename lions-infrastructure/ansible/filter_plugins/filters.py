#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LIONS Infrastructure 5.0 - Custom Ansible Filter Plugins

This module provides specialized Ansible filter plugins designed specifically
for the LIONS Infrastructure deployment and management system.

Features:
- Environment-aware filtering and transformation
- Kubernetes resource management utilities
- Security-focused data handling
- Infrastructure configuration validation
- Multi-environment support with proper defaults

Author: LIONS Infrastructure DevOps Team
Version: 5.0.0
Date: 2025-05-26
License: MIT
Repository: https://github.com/lions-infrastructure/automated-deployment
Documentation: https://docs.lions.dev/ansible/filters
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
import uuid
import urllib.parse
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional, Union, Tuple
from collections import defaultdict

# Version information
__version__ = "5.0.0"
__author__ = "LIONS Infrastructure DevOps Team"
__license__ = "MIT"

# Constants for LIONS Infrastructure
LIONS_ENVIRONMENTS = ['development', 'staging', 'production']
LIONS_RESOURCE_TYPES = ['small', 'medium', 'large', 'xlarge']
LIONS_SECURITY_LEVELS = ['basic', 'standard', 'restricted', 'privileged']

# Kubernetes naming constraints
K8S_NAME_MAX_LENGTH = 63
K8S_LABEL_MAX_LENGTH = 63
K8S_ANNOTATION_MAX_LENGTH = 253

# Password generation defaults
DEFAULT_PASSWORD_LENGTH = 32
DEFAULT_SECRET_LENGTH = 64


class LionsInfrastructureError(Exception):
    """Custom exception for LIONS Infrastructure filter errors."""
    pass


class FilterModule(object):
    """
    Custom Ansible filters for LIONS Infrastructure 5.0.

    This class provides comprehensive filtering capabilities specifically
    designed for the LIONS Infrastructure deployment automation.
    """

    def filters(self):
        """
        Return the complete filter mapping for LIONS Infrastructure.

        Returns:
            dict: Mapping of filter names to their corresponding methods
        """
        return {
            # Core data transformation filters
            'lions_to_yaml': self.lions_to_yaml,
            'lions_from_yaml': self.lions_from_yaml,
            'lions_to_json': self.lions_to_json,
            'lions_from_json': self.lions_from_json,

            # Encoding and security filters
            'lions_b64encode': self.lions_b64encode,
            'lions_b64decode': self.lions_b64decode,
            'lions_hash_password': self.lions_hash_password,
            'lions_generate_secret': self.lions_generate_secret,
            'lions_encrypt_data': self.lions_encrypt_data,

            # Version and comparison filters
            'lions_parse_version': self.lions_parse_version,
            'lions_compare_versions': self.lions_compare_versions,
            'lions_is_compatible_version': self.lions_is_compatible_version,

            # Network and IP filters
            'lions_ip_in_network': self.lions_ip_in_network,
            'lions_generate_ip_range': self.lions_generate_ip_range,
            'lions_validate_cidr': self.lions_validate_cidr,
            'lions_extract_domain': self.lions_extract_domain,
            'lions_build_fqdn': self.lions_build_fqdn,

            # Kubernetes resource filters
            'lions_k8s_name': self.lions_k8s_name,
            'lions_k8s_label': self.lions_k8s_label,
            'lions_k8s_annotation': self.lions_k8s_annotation,
            'lions_k8s_namespace': self.lions_k8s_namespace,
            'lions_k8s_selector': self.lions_k8s_selector,

            # Configuration management filters
            'lions_merge_configs': self.lions_merge_configs,
            'lions_filter_config': self.lions_filter_config,
            'lions_validate_config': self.lions_validate_config,
            'lions_resolve_template': self.lions_resolve_template,

            # Environment-specific filters
            'lions_env_config': self.lions_env_config,
            'lions_env_resources': self.lions_env_resources,
            'lions_env_security': self.lions_env_security,
            'lions_env_domain': self.lions_env_domain,

            # Resource management filters
            'lions_compute_resources': self.lions_compute_resources,
            'lions_storage_size': self.lions_storage_size,
            'lions_resource_limits': self.lions_resource_limits,

            # Service discovery filters
            'lions_service_endpoint': self.lions_service_endpoint,
            'lions_service_url': self.lions_service_url,
            'lions_ingress_rules': self.lions_ingress_rules,

            # Monitoring and health filters
            'lions_health_check': self.lions_health_check,
            'lions_probe_config': self.lions_probe_config,
            'lions_metric_labels': self.lions_metric_labels,

            # Time and scheduling filters
            'lions_format_timestamp': self.lions_format_timestamp,
            'lions_cron_schedule': self.lions_cron_schedule,
            'lions_duration_seconds': self.lions_duration_seconds,

            # Vault integration filters
            'lions_vault_path': self.lions_vault_path,
            'lions_vault_policy': self.lions_vault_policy,
            'lions_vault_secret_spec': self.lions_vault_secret_spec,

            # Backup and maintenance filters
            'lions_backup_schedule': self.lions_backup_schedule,
            'lions_retention_policy': self.lions_retention_policy,
            'lions_maintenance_window': self.lions_maintenance_window,

            # Legacy compatibility filters (maintained for backward compatibility)
            'to_yaml': self.lions_to_yaml,
            'from_yaml': self.lions_from_yaml,
            'to_json': self.lions_to_json,
            'from_json': self.lions_from_json,
            'b64encode': self.lions_b64encode,
            'b64decode': self.lions_b64decode,
            'hash_password': self.lions_hash_password,
            'parse_version': self.lions_parse_version,
            'ip_in_network': self.lions_ip_in_network,
            'format_timestamp': self.lions_format_timestamp,
            'extract_domain': self.lions_extract_domain,
            'k8s_resource_name': self.lions_k8s_name,
            'merge_configs': self.lions_merge_configs,
            'generate_password': self.lions_generate_secret,
        }

    # =========================================================================
    # CORE DATA TRANSFORMATION FILTERS
    # =========================================================================

    def lions_to_yaml(self, data: Any, indent: int = 2, sort_keys: bool = True) -> str:
        """
        Convert data to YAML format with LIONS-specific formatting.

        Args:
            data: Data to convert to YAML
            indent: Number of spaces for indentation
            sort_keys: Whether to sort keys alphabetically

        Returns:
            str: YAML formatted string
        """
        try:
            return yaml.dump(
                data,
                default_flow_style=False,
                indent=indent,
                sort_keys=sort_keys,
                allow_unicode=True,
                width=120
            )
        except Exception as e:
            raise LionsInfrastructureError(f"Failed to convert to YAML: {str(e)}")

    def lions_from_yaml(self, yaml_str: str) -> Any:
        """
        Parse YAML string into data structure with error handling.

        Args:
            yaml_str: YAML string to parse

        Returns:
            Any: Parsed data structure
        """
        try:
            return yaml.safe_load(yaml_str)
        except yaml.YAMLError as e:
            raise LionsInfrastructureError(f"Failed to parse YAML: {str(e)}")

    def lions_to_json(self, data: Any, pretty: bool = False, sort_keys: bool = True) -> str:
        """
        Convert data to JSON format with LIONS-specific formatting.

        Args:
            data: Data to convert to JSON
            pretty: Whether to format with indentation
            sort_keys: Whether to sort keys alphabetically

        Returns:
            str: JSON formatted string
        """
        try:
            if pretty:
                return json.dumps(data, indent=2, sort_keys=sort_keys, ensure_ascii=False)
            return json.dumps(data, sort_keys=sort_keys, ensure_ascii=False)
        except Exception as e:
            raise LionsInfrastructureError(f"Failed to convert to JSON: {str(e)}")

    def lions_from_json(self, json_str: str) -> Any:
        """
        Parse JSON string into data structure with error handling.

        Args:
            json_str: JSON string to parse

        Returns:
            Any: Parsed data structure
        """
        try:
            return json.loads(json_str)
        except json.JSONDecodeError as e:
            raise LionsInfrastructureError(f"Failed to parse JSON: {str(e)}")

    # =========================================================================
    # ENCODING AND SECURITY FILTERS
    # =========================================================================

    def lions_b64encode(self, data: Union[str, bytes]) -> str:
        """
        Encode data as base64 with proper UTF-8 handling.

        Args:
            data: Data to encode (string or bytes)

        Returns:
            str: Base64 encoded string
        """
        try:
            if isinstance(data, str):
                data = data.encode('utf-8')
            return base64.b64encode(data).decode('utf-8')
        except Exception as e:
            raise LionsInfrastructureError(f"Failed to base64 encode: {str(e)}")

    def lions_b64decode(self, data: Union[str, bytes]) -> str:
        """
        Decode base64 data with proper UTF-8 handling.

        Args:
            data: Base64 encoded data to decode

        Returns:
            str: Decoded string
        """
        try:
            if isinstance(data, str):
                data = data.encode('utf-8')
            return base64.b64decode(data).decode('utf-8')
        except Exception as e:
            raise LionsInfrastructureError(f"Failed to base64 decode: {str(e)}")

    def lions_hash_password(self, password: str, salt: Optional[str] = None,
                            algorithm: str = 'sha256', rounds: int = 10000) -> str:
        """
        Hash a password using PBKDF2 with the specified algorithm.

        Args:
            password: Password to hash
            salt: Salt to use (generated if None)
            algorithm: Hash algorithm to use
            rounds: Number of PBKDF2 rounds

        Returns:
            str: Hashed password in format: algorithm$rounds$salt$hash
        """
        try:
            if salt is None:
                salt = base64.b64encode(os.urandom(32)).decode('utf-8')[:32]

            # Use PBKDF2 for stronger password hashing
            hash_obj = hashlib.pbkdf2_hmac(
                algorithm,
                password.encode('utf-8'),
                salt.encode('utf-8'),
                rounds
            )
            hash_hex = hash_obj.hex()

            return f"{algorithm}${rounds}${salt}${hash_hex}"
        except Exception as e:
            raise LionsInfrastructureError(f"Failed to hash password: {str(e)}")

    def lions_generate_secret(self, length: int = DEFAULT_SECRET_LENGTH,
                              charset: str = 'all') -> str:
        """
        Generate a cryptographically secure random secret.

        Args:
            length: Length of the secret to generate
            charset: Character set to use ('all', 'alphanum', 'alpha', 'numeric')

        Returns:
            str: Generated secret
        """
        try:
            if charset == 'all':
                chars = string.ascii_letters + string.digits + '!@#$%^&*()-_=+[]{}|;:,.<>?'
            elif charset == 'alphanum':
                chars = string.ascii_letters + string.digits
            elif charset == 'alpha':
                chars = string.ascii_letters
            elif charset == 'numeric':
                chars = string.digits
            else:
                chars = charset

            # Use cryptographically secure random generator
            return ''.join(random.SystemRandom().choice(chars) for _ in range(length))
        except Exception as e:
            raise LionsInfrastructureError(f"Failed to generate secret: {str(e)}")

    def lions_encrypt_data(self, data: str, key: str, algorithm: str = 'AES') -> str:
        """
        Encrypt data using the specified algorithm (placeholder for future implementation).

        Args:
            data: Data to encrypt
            key: Encryption key
            algorithm: Encryption algorithm

        Returns:
            str: Encrypted data (base64 encoded)
        """
        # This is a placeholder - actual encryption would require additional libraries
        # For now, return base64 encoded data with a warning
        encoded = self.lions_b64encode(data)
        return f"PLACEHOLDER_ENCRYPTED_{algorithm}_{encoded}"

    # =========================================================================
    # VERSION AND COMPARISON FILTERS
    # =========================================================================

    def lions_parse_version(self, version_str: str) -> Tuple[int, int, int]:
        """
        Parse a version string into a comparable tuple.

        Args:
            version_str: Version string to parse (e.g., "1.2.3", "v1.2.3+k3s1")

        Returns:
            Tuple[int, int, int]: Version tuple (major, minor, patch)
        """
        if not version_str:
            return (0, 0, 0)

        # Remove common prefixes
        version_str = re.sub(r'^v', '', version_str)

        # Extract version components (handle various formats)
        patterns = [
            r'(\d+)\.(\d+)\.(\d+)',  # x.y.z
            r'(\d+)\.(\d+)',         # x.y
            r'(\d+)'                 # x
        ]

        for pattern in patterns:
            match = re.search(pattern, version_str)
            if match:
                groups = match.groups()
                if len(groups) == 3:
                    return tuple(int(x) for x in groups)
                elif len(groups) == 2:
                    return (int(groups[0]), int(groups[1]), 0)
                else:
                    return (int(groups[0]), 0, 0)

        return (0, 0, 0)

    def lions_compare_versions(self, version1: str, version2: str) -> int:
        """
        Compare two version strings.

        Args:
            version1: First version string
            version2: Second version string

        Returns:
            int: -1 if version1 < version2, 0 if equal, 1 if version1 > version2
        """
        v1 = self.lions_parse_version(version1)
        v2 = self.lions_parse_version(version2)

        if v1 < v2:
            return -1
        elif v1 > v2:
            return 1
        else:
            return 0

    def lions_is_compatible_version(self, current: str, required: str,
                                    compatibility: str = 'minor') -> bool:
        """
        Check if current version is compatible with required version.

        Args:
            current: Current version string
            required: Required version string
            compatibility: Compatibility level ('major', 'minor', 'patch')

        Returns:
            bool: True if compatible, False otherwise
        """
        curr = self.lions_parse_version(current)
        req = self.lions_parse_version(required)

        if compatibility == 'major':
            return curr[0] == req[0] and curr >= req
        elif compatibility == 'minor':
            return curr[0] == req[0] and curr[1] == req[1] and curr >= req
        elif compatibility == 'patch':
            return curr == req
        else:
            return curr >= req

    # =========================================================================
    # NETWORK AND IP FILTERS
    # =========================================================================

    def lions_ip_in_network(self, ip: str, network: str) -> bool:
        """
        Check if an IP address is within a network range.

        Args:
            ip: IP address to check
            network: Network range in CIDR notation

        Returns:
            bool: True if IP is in network, False otherwise
        """
        try:
            return ipaddress.ip_address(ip) in ipaddress.ip_network(network, strict=False)
        except ValueError as e:
            raise LionsInfrastructureError(f"Invalid IP or network: {str(e)}")

    def lions_generate_ip_range(self, network: str, start_offset: int = 10,
                                count: int = 50) -> List[str]:
        """
        Generate a list of IP addresses from a network range.

        Args:
            network: Network range in CIDR notation
            start_offset: Offset from network start
            count: Number of IPs to generate

        Returns:
            List[str]: List of IP addresses
        """
        try:
            net = ipaddress.ip_network(network, strict=False)
            hosts = list(net.hosts())

            if start_offset >= len(hosts):
                return []

            end_offset = min(start_offset + count, len(hosts))
            return [str(ip) for ip in hosts[start_offset:end_offset]]
        except ValueError as e:
            raise LionsInfrastructureError(f"Invalid network range: {str(e)}")

    def lions_validate_cidr(self, cidr: str) -> bool:
        """
        Validate a CIDR notation network range.

        Args:
            cidr: CIDR notation to validate

        Returns:
            bool: True if valid, False otherwise
        """
        try:
            ipaddress.ip_network(cidr, strict=False)
            return True
        except ValueError:
            return False

    def lions_extract_domain(self, url: str) -> str:
        """
        Extract the domain from a URL.

        Args:
            url: URL to extract domain from

        Returns:
            str: Extracted domain
        """
        if not url:
            return ""

        try:
            parsed = urllib.parse.urlparse(url if url.startswith(('http://', 'https://')) else f'http://{url}')
            return parsed.netloc
        except Exception:
            # Fallback to regex for malformed URLs
            match = re.search(r'(?:https?://)?([^/]+)', url)
            return match.group(1) if match else url

    def lions_build_fqdn(self, service: str, namespace: str = None,
                         domain: str = None, environment: str = None) -> str:
        """
        Build a fully qualified domain name for a service.

        Args:
            service: Service name
            namespace: Kubernetes namespace
            domain: Base domain
            environment: Environment name

        Returns:
            str: Fully qualified domain name
        """
        parts = []

        # Add service name
        parts.append(self.lions_k8s_name(service))

        # Add namespace if provided
        if namespace:
            parts.append(self.lions_k8s_name(namespace))

        # Add environment if provided
        if environment:
            parts.append(environment)

        # Add domain if provided
        if domain:
            parts.append(domain)

        return '.'.join(parts)

    # =========================================================================
    # KUBERNETES RESOURCE FILTERS
    # =========================================================================

    def lions_k8s_name(self, name: str, prefix: str = None, suffix: str = None) -> str:
        """
        Convert a string to a valid Kubernetes resource name.

        Args:
            name: Name to convert
            prefix: Optional prefix to add
            suffix: Optional suffix to add

        Returns:
            str: Valid Kubernetes resource name
        """
        if not name:
            raise LionsInfrastructureError("Name cannot be empty")

        # Build full name with prefix and suffix
        full_name = name
        if prefix:
            full_name = f"{prefix}-{full_name}"
        if suffix:
            full_name = f"{full_name}-{suffix}"

        # Convert to lowercase and replace invalid characters
        k8s_name = re.sub(r'[^a-z0-9-]', '-', full_name.lower())

        # Remove leading and trailing dashes
        k8s_name = k8s_name.strip('-')

        # Replace multiple consecutive dashes with a single dash
        k8s_name = re.sub(r'-+', '-', k8s_name)

        # Ensure name is not longer than 63 characters
        if len(k8s_name) > K8S_NAME_MAX_LENGTH:
            k8s_name = k8s_name[:K8S_NAME_MAX_LENGTH].rstrip('-')

        # Ensure name is not empty after processing
        if not k8s_name:
            k8s_name = 'lions-resource'

        return k8s_name

    def lions_k8s_label(self, key: str, value: str) -> Dict[str, str]:
        """
        Create a valid Kubernetes label.

        Args:
            key: Label key
            value: Label value

        Returns:
            Dict[str, str]: Valid Kubernetes label
        """
        # Validate and clean key
        clean_key = re.sub(r'[^a-zA-Z0-9._-]', '-', key)
        if len(clean_key) > K8S_LABEL_MAX_LENGTH:
            clean_key = clean_key[:K8S_LABEL_MAX_LENGTH]

        # Validate and clean value
        clean_value = re.sub(r'[^a-zA-Z0-9._-]', '-', str(value))
        if len(clean_value) > K8S_LABEL_MAX_LENGTH:
            clean_value = clean_value[:K8S_LABEL_MAX_LENGTH]

        return {clean_key: clean_value}

    def lions_k8s_annotation(self, key: str, value: str) -> Dict[str, str]:
        """
        Create a valid Kubernetes annotation.

        Args:
            key: Annotation key
            value: Annotation value

        Returns:
            Dict[str, str]: Valid Kubernetes annotation
        """
        # Annotations are more flexible than labels
        clean_key = key
        if len(clean_key) > K8S_ANNOTATION_MAX_LENGTH:
            clean_key = clean_key[:K8S_ANNOTATION_MAX_LENGTH]

        return {clean_key: str(value)}

    def lions_k8s_namespace(self, name: str, environment: str = None) -> str:
        """
        Generate a valid Kubernetes namespace name.

        Args:
            name: Base namespace name
            environment: Environment name to append

        Returns:
            str: Valid Kubernetes namespace name
        """
        namespace_parts = [name]
        if environment:
            namespace_parts.append(environment)

        return self.lions_k8s_name('-'.join(namespace_parts))

    def lions_k8s_selector(self, labels: Dict[str, str]) -> str:
        """
        Convert a dictionary of labels to a Kubernetes selector string.

        Args:
            labels: Dictionary of labels

        Returns:
            str: Kubernetes selector string
        """
        if not labels:
            return ""

        selectors = []
        for key, value in labels.items():
            selectors.append(f"{key}={value}")

        return ','.join(selectors)

    # =========================================================================
    # CONFIGURATION MANAGEMENT FILTERS
    # =========================================================================

    def lions_merge_configs(self, base_config: Dict[str, Any],
                            *override_configs: Dict[str, Any]) -> Dict[str, Any]:
        """
        Recursively merge multiple configuration dictionaries.

        Args:
            base_config: Base configuration dictionary
            *override_configs: Additional configuration dictionaries to merge

        Returns:
            Dict[str, Any]: Merged configuration dictionary
        """
        def _deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
            result = base.copy()

            for key, value in override.items():
                if (key in result and
                        isinstance(result[key], dict) and
                        isinstance(value, dict)):
                    result[key] = _deep_merge(result[key], value)
                else:
                    result[key] = value

            return result

        result = base_config.copy()
        for override_config in override_configs:
            result = _deep_merge(result, override_config)

        return result

    def lions_filter_config(self, config: Dict[str, Any],
                            include_keys: List[str] = None,
                            exclude_keys: List[str] = None) -> Dict[str, Any]:
        """
        Filter configuration dictionary by including or excluding specific keys.

        Args:
            config: Configuration dictionary to filter
            include_keys: Keys to include (if None, include all)
            exclude_keys: Keys to exclude

        Returns:
            Dict[str, Any]: Filtered configuration dictionary
        """
        result = {}

        for key, value in config.items():
            # Check if key should be included
            if include_keys is not None and key not in include_keys:
                continue

            # Check if key should be excluded
            if exclude_keys is not None and key in exclude_keys:
                continue

            result[key] = value

        return result

    def lions_validate_config(self, config: Dict[str, Any],
                              required_keys: List[str] = None,
                              schema: Dict[str, Any] = None) -> bool:
        """
        Validate configuration dictionary against requirements.

        Args:
            config: Configuration dictionary to validate
            required_keys: List of required keys
            schema: Schema for validation (simplified)

        Returns:
            bool: True if valid, False otherwise
        """
        if required_keys:
            for key in required_keys:
                if key not in config:
                    return False

        if schema:
            for key, expected_type in schema.items():
                if key in config and not isinstance(config[key], expected_type):
                    return False

        return True

    def lions_resolve_template(self, template: str, variables: Dict[str, Any]) -> str:
        """
        Resolve template variables in a string.

        Args:
            template: Template string with variables
            variables: Dictionary of variables to substitute

        Returns:
            str: Resolved template string
        """
        try:
            # Simple template resolution using string formatting
            return template.format(**variables)
        except KeyError as e:
            raise LionsInfrastructureError(f"Missing template variable: {str(e)}")
        except Exception as e:
            raise LionsInfrastructureError(f"Template resolution failed: {str(e)}")

    # =========================================================================
    # ENVIRONMENT-SPECIFIC FILTERS
    # =========================================================================

    def lions_env_config(self, environment: str,
                         default_config: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Get environment-specific configuration.

        Args:
            environment: Environment name
            default_config: Default configuration to use as base

        Returns:
            Dict[str, Any]: Environment-specific configuration
        """
        if environment not in LIONS_ENVIRONMENTS:
            raise LionsInfrastructureError(f"Invalid environment: {environment}")

        base_config = default_config or {}

        # Environment-specific overrides
        env_overrides = {
            'development': {
                'debug': True,
                'log_level': 'DEBUG',
                'replicas': 1,
                'resources': 'small'
            },
            'staging': {
                'debug': False,
                'log_level': 'INFO',
                'replicas': 2,
                'resources': 'medium'
            },
            'production': {
                'debug': False,
                'log_level': 'WARN',
                'replicas': 3,
                'resources': 'large'
            }
        }

        return self.lions_merge_configs(base_config, env_overrides.get(environment, {}))

    def lions_env_resources(self, environment: str,
                            resource_type: str = 'medium') -> Dict[str, str]:
        """
        Get resource specifications for an environment.

        Args:
            environment: Environment name
            resource_type: Resource type (small, medium, large, xlarge)

        Returns:
            Dict[str, str]: Resource specifications
        """
        if resource_type not in LIONS_RESOURCE_TYPES:
            raise LionsInfrastructureError(f"Invalid resource type: {resource_type}")

        # Base resource specifications
        resources = {
            'small': {
                'cpu_request': '100m',
                'cpu_limit': '500m',
                'memory_request': '128Mi',
                'memory_limit': '512Mi'
            },
            'medium': {
                'cpu_request': '200m',
                'cpu_limit': '1000m',
                'memory_request': '512Mi',
                'memory_limit': '2Gi'
            },
            'large': {
                'cpu_request': '500m',
                'cpu_limit': '2000m',
                'memory_request': '1Gi',
                'memory_limit': '4Gi'
            },
            'xlarge': {
                'cpu_request': '1000m',
                'cpu_limit': '4000m',
                'memory_request': '2Gi',
                'memory_limit': '8Gi'
            }
        }

        # Environment-specific multipliers
        multipliers = {
            'development': 0.5,
            'staging': 0.8,
            'production': 1.0
        }

        base_resources = resources[resource_type]
        multiplier = multipliers.get(environment, 1.0)

        # Apply multiplier to numeric values
        adjusted_resources = {}
        for key, value in base_resources.items():
            if 'm' in value:  # CPU values
                numeric_value = int(value.replace('m', ''))
                adjusted_resources[key] = f"{int(numeric_value * multiplier)}m"
            elif 'Mi' in value or 'Gi' in value:  # Memory values
                # Keep memory values as-is for simplicity
                adjusted_resources[key] = value
            else:
                adjusted_resources[key] = value

        return adjusted_resources

    def lions_env_security(self, environment: str) -> Dict[str, Any]:
        """
        Get security configuration for an environment.

        Args:
            environment: Environment name

        Returns:
            Dict[str, Any]: Security configuration
        """
        security_configs = {
            'development': {
                'pod_security_standard': 'baseline',
                'network_policies': False,
                'tls_required': False,
                'rbac_strict': False
            },
            'staging': {
                'pod_security_standard': 'restricted',
                'network_policies': True,
                'tls_required': True,
                'rbac_strict': True
            },
            'production': {
                'pod_security_standard': 'restricted',
                'network_policies': True,
                'tls_required': True,
                'rbac_strict': True,
                'audit_logging': True,
                'secret_encryption': True
            }
        }

        return security_configs.get(environment, security_configs['development'])

    def lions_env_domain(self, environment: str, base_domain: str,
                         service: str = None) -> str:
        """
        Generate environment-specific domain name.

        Args:
            environment: Environment name
            base_domain: Base domain name
            service: Optional service name

        Returns:
            str: Environment-specific domain name
        """
        parts = []

        if service:
            parts.append(service)

        if environment != 'production':
            parts.append(environment)

        parts.append(base_domain)

        return '.'.join(parts)

    # =========================================================================
    # ADDITIONAL UTILITY FILTERS
    # =========================================================================

    def lions_compute_resources(self, workload_type: str,
                                environment: str = 'development') -> Dict[str, str]:
        """
        Compute appropriate resources for a workload type.

        Args:
            workload_type: Type of workload (web, api, database, etc.)
            environment: Environment name

        Returns:
            Dict[str, str]: Resource specifications
        """
        workload_resources = {
            'web': 'small',
            'api': 'medium',
            'database': 'large',
            'cache': 'medium',
            'worker': 'medium',
            'monitoring': 'small',
            'ai': 'xlarge'
        }

        resource_type = workload_resources.get(workload_type, 'medium')
        return self.lions_env_resources(environment, resource_type)

    def lions_storage_size(self, storage_type: str, environment: str = 'development') -> str:
        """
        Get appropriate storage size for a storage type and environment.

        Args:
            storage_type: Type of storage (database, cache, logs, etc.)
            environment: Environment name

        Returns:
            str: Storage size specification
        """
        base_sizes = {
            'database': {'development': '10Gi', 'staging': '50Gi', 'production': '200Gi'},
            'cache': {'development': '1Gi', 'staging': '5Gi', 'production': '20Gi'},
            'logs': {'development': '5Gi', 'staging': '20Gi', 'production': '100Gi'},
            'backup': {'development': '20Gi', 'staging': '100Gi', 'production': '500Gi'},
            'ai_models': {'development': '50Gi', 'staging': '100Gi', 'production': '500Gi'}
        }

        return base_sizes.get(storage_type, {}).get(environment, '10Gi')

    def lions_format_timestamp(self, timestamp: Union[datetime, float, str, None] = None,
                               format_str: str = "%Y-%m-%d %H:%M:%S UTC",
                               timezone_aware: bool = True) -> str:
        """
        Format a timestamp with timezone awareness.

        Args:
            timestamp: Timestamp to format (defaults to current time)
            format_str: Format string
            timezone_aware: Whether to use UTC timezone

        Returns:
            str: Formatted timestamp string
        """
        if timestamp is None:
            timestamp = datetime.now(timezone.utc) if timezone_aware else datetime.now()
        elif isinstance(timestamp, (int, float)):
            timestamp = datetime.fromtimestamp(timestamp, timezone.utc if timezone_aware else None)
        elif isinstance(timestamp, str):
            try:
                timestamp = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            except ValueError:
                try:
                    timestamp = datetime.fromtimestamp(float(timestamp), timezone.utc if timezone_aware else None)
                except ValueError:
                    return timestamp

        return timestamp.strftime(format_str)

    def lions_vault_path(self, service: str, environment: str,
                         secret_type: str = 'config') -> str:
        """
        Generate a Vault path for storing secrets.

        Args:
            service: Service name
            environment: Environment name
            secret_type: Type of secret (config, credentials, etc.)

        Returns:
            str: Vault path
        """
        return f"secret/lions/{environment}/{service}/{secret_type}"

    def lions_health_check(self, service_type: str, port: int = None) -> Dict[str, Any]:
        """
        Generate health check configuration for a service type.

        Args:
            service_type: Type of service (web, api, database, etc.)
            port: Port number for health checks

        Returns:
            Dict[str, Any]: Health check configuration
        """
        health_configs = {
            'web': {
                'path': '/health',
                'port': port or 80,
                'initial_delay': 30,
                'period': 10,
                'timeout': 5,
                'failure_threshold': 3
            },
            'api': {
                'path': '/health',
                'port': port or 8080,
                'initial_delay': 45,
                'period': 15,
                'timeout': 10,
                'failure_threshold': 3
            },
            'database': {
                'command': ['pg_isready'] if not port or port == 5432 else ['redis-cli', 'ping'],
                'initial_delay': 60,
                'period': 30,
                'timeout': 10,
                'failure_threshold': 5
            }
        }

        return health_configs.get(service_type, health_configs['web'])

    def lions_duration_seconds(self, duration: str) -> int:
        """
        Convert a duration string to seconds.

        Args:
            duration: Duration string (e.g., "1h", "30m", "45s")

        Returns:
            int: Duration in seconds
        """
        pattern = r'(\d+)([hms])'
        matches = re.findall(pattern, duration.lower())

        total_seconds = 0
        for value, unit in matches:
            if unit == 'h':
                total_seconds += int(value) * 3600
            elif unit == 'm':
                total_seconds += int(value) * 60
            elif unit == 's':
                total_seconds += int(value)

        return total_seconds or 0
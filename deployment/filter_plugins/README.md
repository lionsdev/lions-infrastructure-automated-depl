# Ansible Filter Plugins for LIONS Infrastructure

This directory contains custom Ansible filter plugins used in the LIONS Infrastructure project.

## Overview

Filter plugins in Ansible allow you to manipulate data within your playbooks and templates. The custom filters in this directory extend Ansible's built-in filters with additional functionality specific to the LIONS Infrastructure project.

## Available Filters

The following custom filters are available in the `filters.py` file:

### Data Conversion Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `to_yaml` | Convert data to YAML format | `{{ my_dict \| to_yaml }}` |
| `from_yaml` | Parse YAML string into data structure | `{{ yaml_string \| from_yaml }}` |
| `to_json` | Convert data to JSON format | `{{ my_dict \| to_json(pretty=true) }}` |
| `from_json` | Parse JSON string into data structure | `{{ json_string \| from_json }}` |
| `b64encode` | Encode data as base64 | `{{ my_string \| b64encode }}` |
| `b64decode` | Decode base64 data | `{{ encoded_string \| b64decode }}` |

### Security Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `hash_password` | Hash a password using the specified algorithm | `{{ 'mypassword' \| hash_password(salt='mysalt', algorithm='sha256') }}` |
| `generate_password` | Generate a random password | `{{ 16 \| generate_password(include_special=true) }}` |

### Version Handling Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `parse_version` | Parse a version string into a comparable tuple | `{{ '1.2.3' \| parse_version }}` |

### Network Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `ip_in_network` | Check if an IP address is within a network range | `{{ '192.168.1.10' \| ip_in_network('192.168.1.0/24') }}` |
| `extract_domain` | Extract the domain from a URL | `{{ 'https://example.com/path' \| extract_domain }}` |

### Date and Time Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `format_timestamp` | Format a timestamp according to the specified format | `{{ '2025-05-24T12:34:56' \| format_timestamp('%Y-%m-%d %H:%M:%S') }}` |

### Kubernetes Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `k8s_resource_name` | Convert a string to a valid Kubernetes resource name | `{{ 'My App 1.0' \| k8s_resource_name }}` |
| `filter_pods` | Filter a list of pods based on namespace, labels, and status | `{{ pods \| filter_pods(namespace='default', status='Running') }}` |

### Configuration Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `merge_configs` | Recursively merge two configuration dictionaries | `{{ base_config \| merge_configs(override_config) }}` |

## Usage in Playbooks

To use these filters in your playbooks, simply apply them to variables using the pipe (`|`) operator:

```yaml
---
- name: Example playbook using custom filters
  hosts: all
  vars:
    my_config:
      key1: value1
      key2: value2
    override_config:
      key2: new_value
      key3: value3
  
  tasks:
    - name: Merge configurations
      set_fact:
        merged_config: "{{ my_config | merge_configs(override_config) }}"
    
    - name: Show merged config as YAML
      debug:
        msg: "{{ merged_config | to_yaml }}"
    
    - name: Generate a random password
      set_fact:
        random_password: "{{ 16 | generate_password }}"
    
    - name: Show the generated password
      debug:
        msg: "Generated password: {{ random_password }}"
```

## Usage in Templates

These filters can also be used in Jinja2 templates:

```jinja
# Kubernetes manifest template
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ application_name | k8s_resource_name }}
  namespace: {{ namespace }}
data:
  config.json: |
    {{ config_data | to_json(pretty=true) }}
```

## Adding New Filters

To add a new filter:

1. Edit the `filters.py` file
2. Add your filter function to the `FilterModule` class
3. Add the filter to the dictionary returned by the `filters()` method
4. Document your filter in this README.md file

Example:

```python
def my_new_filter(self, value, arg1=None):
    """Description of what the filter does."""
    # Filter implementation
    return result

def filters(self):
    return {
        # Existing filters...
        'my_new_filter': self.my_new_filter,
    }
```

## Testing Filters

You can test these filters using the Ansible `debug` module:

```yaml
- name: Test filter
  debug:
    msg: "{{ 'test' | my_new_filter }}"
```

Or using the `ansible-playbook` command with the `--check` flag to run in check mode.
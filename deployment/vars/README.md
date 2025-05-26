# Ansible Variables for LIONS Infrastructure

This directory contains variable files used by Ansible playbooks and roles in the LIONS Infrastructure project.

## Overview

The variable files are organized in a hierarchical structure:

1. **common.yml**: Base variables used across all environments
2. **Environment-specific files**: Override common variables for specific environments
   - **development.yml**: Development environment
   - **staging.yml**: Staging/pre-production environment
   - **production.yml**: Production environment

## Usage

Variables are loaded in the following order:

1. Common variables from `common.yml`
2. Environment-specific variables (e.g., `development.yml`, `staging.yml`, or `production.yml`)
3. Command-line variables (highest precedence)

This allows for a flexible configuration where you can define defaults in `common.yml` and override them as needed in environment-specific files or via command-line parameters.

### Example Usage in Playbooks

```yaml
---
- name: Example playbook
  hosts: all
  vars_files:
    - "../vars/common.yml"
    - "../vars/{{ lions_env | default('development') }}.yml"
  
  tasks:
    - name: Show environment
      debug:
        msg: "Running in {{ lions_env }} environment"
```

## Variable Categories

The variable files contain settings for various aspects of the infrastructure:

- **Environment settings**: Basic environment configuration
- **VPS settings**: Server configuration
- **Kubernetes settings**: K3s and Kubernetes configuration
- **Component versions**: Version numbers for various components
- **Resource settings**: CPU and memory allocations
- **Storage settings**: Storage configuration
- **Security settings**: Security-related configuration
- **Component enablement**: Flags to enable/disable components
- **Monitoring configuration**: Prometheus and Grafana settings
- **Service domains**: Domain names for various services
- **Default credentials**: Default usernames and passwords
- **Backup configuration**: Backup settings
- **Logging configuration**: Logging settings
- **High availability settings**: HA configuration (production only)
- **Performance settings**: Performance tuning (production only)
- **Alerting configuration**: Alert notification settings (production only)

## Environment-Specific Configurations

### Development Environment

The development environment (`development.yml`) is configured with:
- Reduced resource requirements
- Simplified security settings
- More verbose logging
- Simple passwords for easier development
- Some components disabled to save resources

### Staging Environment

The staging environment (`staging.yml`) is configured with:
- Moderate resource allocations
- Enhanced security settings
- Balanced logging configuration
- Stronger passwords
- Most components enabled

### Production Environment

The production environment (`production.yml`) is configured with:
- Optimized resource allocations
- Maximum security settings
- Comprehensive logging and monitoring
- Credentials sourced from environment variables (no defaults)
- All components enabled
- High availability settings
- Performance optimizations
- Comprehensive alerting configuration

## Best Practices

1. **Never store sensitive information** directly in these files. Use environment variables or Ansible Vault.
2. **Test changes** in development and staging before applying to production.
3. **Document any changes** you make to these files.
4. **Keep versions consistent** across environments when possible.
5. **Use environment variables** for configuration that varies between deployments.

## Adding New Variables

When adding new variables:

1. Add the default value to `common.yml`
2. Override as needed in environment-specific files
3. Document the variable's purpose with comments
4. Follow the existing naming conventions
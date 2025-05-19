package lionsctl

import (
	"testing"
)

func TestEnvironment(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
		wantErr  bool
	}{
		// Tests pour les environnements standards de LIONS
		{
			name:     "development environment",
			input:    "development",
			expected: "development",
			wantErr:  false,
		},
		{
			name:     "staging environment",
			input:    "staging",
			expected: "staging",
			wantErr:  false,
		},
		{
			name:     "production environment",
			input:    "production",
			expected: "production",
			wantErr:  false,
		},
		// Tests pour les environnements hérités de sigctlv2
		{
			name:     "default environment",
			input:    "default",
			expected: "default",
			wantErr:  false,
		},
		{
			name:     "prod environment",
			input:    "prod",
			expected: "prod",
			wantErr:  false,
		},
		{
			name:     "preprod environment",
			input:    "preprod",
			expected: "preprod",
			wantErr:  false,
		},
		{
			name:     "debug environment",
			input:    "debug",
			expected: "debug",
			wantErr:  false,
		},
		{
			name:     "dev environment",
			input:    "dev",
			expected: "dev",
			wantErr:  false,
		},
		// Test pour un environnement non supporté
		{
			name:     "unsupported environment",
			input:    "unknown",
			expected: "",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := environment(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("environment() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.expected {
				t.Errorf("environment() = %v, want %v", got, tt.expected)
			}
		})
	}
}

func TestK8sConfigfile(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
		wantErr  bool
	}{
		{
			name:     "k1 cluster",
			input:    "k1",
			expected: "k8sv1-admin.conf",
			wantErr:  false,
		},
		{
			name:     "k2 cluster",
			input:    "k2",
			expected: "k8sv2-admin.conf",
			wantErr:  false,
		},
		{
			name:     "unsupported cluster",
			input:    "k3",
			expected: "",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := k8sConfigfile(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("k8sConfigfile() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.expected {
				t.Errorf("k8sConfigfile() = %v, want %v", got, tt.expected)
			}
		})
	}
}
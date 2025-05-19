package lionsctl

import (
	"testing"
	"reflect"
)

func TestNewCreateGitRepoOtions(t *testing.T) {
	tests := []struct {
		name          string
		appName       string
		cluster       string
		defaultBranch string
		autoInit      bool
		expected      CreateGitRepoOptions
	}{
		{
			name:          "Standard options",
			appName:       "my-application",
			cluster:       "k2",
			defaultBranch: "main",
			autoInit:      false,
			expected: CreateGitRepoOptions{
				AutoInit:      false,
				DefaultBranch: "main",
				Description:   "",
				Gitignores:    "",
				IssueLabels:   "",
				License:       "",
				Name:          "my-application-k2",
				Private:       false,
				Readme:        "",
				Template:      true,
				TrustModel:    "",
			},
		},
		{
			name:          "With auto init",
			appName:       "test-app",
			cluster:       "k1",
			defaultBranch: "develop",
			autoInit:      true,
			expected: CreateGitRepoOptions{
				AutoInit:      true,
				DefaultBranch: "develop",
				Description:   "",
				Gitignores:    "",
				IssueLabels:   "",
				License:       "",
				Name:          "test-app-k1",
				Private:       false,
				Readme:        "",
				Template:      true,
				TrustModel:    "",
			},
		},
		{
			name:          "Empty app name",
			appName:       "",
			cluster:       "k2",
			defaultBranch: "main",
			autoInit:      false,
			expected: CreateGitRepoOptions{
				AutoInit:      false,
				DefaultBranch: "main",
				Description:   "",
				Gitignores:    "",
				IssueLabels:   "",
				License:       "",
				Name:          "-k2",
				Private:       false,
				Readme:        "",
				Template:      true,
				TrustModel:    "",
			},
		},
		{
			name:          "Empty cluster",
			appName:       "my-application",
			cluster:       "",
			defaultBranch: "main",
			autoInit:      false,
			expected: CreateGitRepoOptions{
				AutoInit:      false,
				DefaultBranch: "main",
				Description:   "",
				Gitignores:    "",
				IssueLabels:   "",
				License:       "",
				Name:          "my-application-",
				Private:       false,
				Readme:        "",
				Template:      true,
				TrustModel:    "",
			},
		},
		{
			name:          "Empty default branch",
			appName:       "my-application",
			cluster:       "k2",
			defaultBranch: "",
			autoInit:      false,
			expected: CreateGitRepoOptions{
				AutoInit:      false,
				DefaultBranch: "",
				Description:   "",
				Gitignores:    "",
				IssueLabels:   "",
				License:       "",
				Name:          "my-application-k2",
				Private:       false,
				Readme:        "",
				Template:      true,
				TrustModel:    "",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := NewCreateGitRepoOtions(tt.appName, tt.cluster, tt.defaultBranch, tt.autoInit)
			if !reflect.DeepEqual(got, tt.expected) {
				t.Errorf("NewCreateGitRepoOtions() = %v, want %v", got, tt.expected)
			}
		})
	}
}
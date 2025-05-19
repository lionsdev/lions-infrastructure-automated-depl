package lionsctl

import (
	"testing"
	"github.com/spf13/viper"
)

func TestAppName(t *testing.T) {
	tests := []struct {
		name     string
		gitUrl   string
		expected string
		wantErr  bool
	}{
		{
			name:     "GitHub URL with .git suffix",
			gitUrl:   "https://github.com/lionsdev/my-application.git",
			expected: "my-application",
			wantErr:  false,
		},
		{
			name:     "GitHub URL without .git suffix",
			gitUrl:   "https://github.com/lionsdev/my-application",
			expected: "my-application",
			wantErr:  false,
		},
		{
			name:     "GitHub URL with organization and project",
			gitUrl:   "https://github.com/lionsdev/lions-infrastructure",
			expected: "lions-infrastructure",
			wantErr:  false,
		},
		{
			name:     "Invalid URL",
			gitUrl:   "://invalid-url",
			expected: "",
			wantErr:  true,
		},
		{
			name:     "Empty URL",
			gitUrl:   "",
			expected: "",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := AppName(tt.gitUrl)
			if (err != nil) != tt.wantErr {
				t.Errorf("AppName() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.expected {
				t.Errorf("AppName() = %v, want %v", got, tt.expected)
			}
		})
	}
}

func TestConfigRepoName(t *testing.T) {
	tests := []struct {
		name     string
		appName  string
		cluster  string
		expected string
	}{
		{
			name:     "Standard app name and cluster",
			appName:  "my-application",
			cluster:  "k2",
			expected: "my-application-k2",
		},
		{
			name:     "Empty app name",
			appName:  "",
			cluster:  "k1",
			expected: "-k1",
		},
		{
			name:     "Empty cluster",
			appName:  "my-application",
			cluster:  "",
			expected: "my-application-",
		},
		{
			name:     "Both empty",
			appName:  "",
			cluster:  "",
			expected: "-",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ConfigRepoName(tt.appName, tt.cluster)
			if got != tt.expected {
				t.Errorf("ConfigRepoName() = %v, want %v", got, tt.expected)
			}
		})
	}
}

func TestConfigUrl(t *testing.T) {
	// Sauvegarde des valeurs originales de viper
	oldDomain := viper.GetString("GIT.DOMAIN")
	oldUsername := viper.GetString("GIT.CFG_USERNAME")
	oldPassword := viper.GetString("GIT.CFG_PASSWORD")

	// Restauration des valeurs originales à la fin du test
	defer func() {
		viper.Set("GIT.DOMAIN", oldDomain)
		viper.Set("GIT.CFG_USERNAME", oldUsername)
		viper.Set("GIT.CFG_PASSWORD", oldPassword)
	}()

	// Configuration de viper pour les tests
	viper.Set("GIT.DOMAIN", "github.com")
	viper.Set("GIT.CFG_USERNAME", "testuser")
	viper.Set("GIT.CFG_PASSWORD", "testpass")

	tests := []struct {
		name     string
		appName  string
		cluster  string
		expected string
		wantErr  bool
	}{
		{
			name:     "Standard app name and cluster",
			appName:  "my-application",
			cluster:  "k2",
			expected: "https://testuser:testpass@github.com/testuser/my-application-k2",
			wantErr:  false,
		},
		{
			name:     "Empty app name",
			appName:  "",
			cluster:  "k1",
			expected: "https://testuser:testpass@github.com/testuser/-k1",
			wantErr:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ConfigUrl(tt.appName, tt.cluster)
			if (err != nil) != tt.wantErr {
				t.Errorf("ConfigUrl() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.expected {
				t.Errorf("ConfigUrl() = %v, want %v", got, tt.expected)
			}
		})
	}
}

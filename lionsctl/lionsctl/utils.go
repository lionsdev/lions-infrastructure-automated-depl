package lionsctl

import (
	"bytes"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"

	"github.com/spf13/viper"
)

func AppName(gitUrl string) (string, error) {
	u, err := url.Parse(gitUrl)
	if err != nil {
		return "", err
	}

	path := u.Path
	parts := strings.Split(path, "/")
	name := parts[len(parts)-1]
	name = strings.TrimSuffix(name, ".git")

	return name, nil
}

func ConfigUrl(appName, cluster string) (string, error) {
	repoName := ConfigRepoName(appName, cluster)

	// Construire l'URL de base avec url.JoinPath
	baseUrl, err := url.JoinPath("https://", viper.GetString("GIT.DOMAIN"), viper.GetString("GIT.CFG_USERNAME"), repoName)
	if err != nil {
		return "", err
	}

	// Ajouter les informations d'authentification
	u, err := url.Parse(baseUrl)
	if err != nil {
		return "", err
	}

	// Définir les informations d'authentification
	u.User = url.UserPassword(viper.GetString("GIT.CFG_USERNAME"), viper.GetString("GIT.CFG_PASSWORD"))

	return u.String(), nil
}

func ConfigRepoName(name, cluster string) string {
	return name + "-" + cluster
}

func request(url, method string, body []byte) error {
	log.Printf("--- REQUEST URL: %s", url)
	log.Printf("--- REQUEST METHOD: %s", method)

	bodyReader := bytes.NewReader(body)
	req, err := http.NewRequest(method, url, bodyReader)
	if err != nil {
		return err
	}

	req.Header.Set("accept", "application/json")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "token "+viper.GetString("GIT.ACCESS_TOKENS"))

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	log.Printf("--- RESPONSE STATUS: %s", resp.Status)

	// Utiliser un buffer pour lire le corps de la réponse
	buff := new(bytes.Buffer)
	_, err = buff.ReadFrom(resp.Body)
	if err != nil {
		return err
	}

	log.Printf("--- RESPONSE BODY: %s", buff.String())

	if resp.StatusCode >= 400 {
		return fmt.Errorf("request failed with status: %s", resp.Status)
	}

	return nil
}

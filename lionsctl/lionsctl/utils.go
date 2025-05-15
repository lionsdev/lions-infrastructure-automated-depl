package lionsctl

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"strings"

	"github.com/spf13/viper"
)

func AppName(url string) (string, error) {
	parts := strings.Split(url, "/")
	if len(parts) == 0 {
		return "", fmt.Errorf("invalid url: %s", url)
	}

	name := parts[len(parts)-1]
	name = strings.TrimSuffix(name, ".git")

	return name, nil
}

func ConfigUrl(appName, cluster string) (string, error) {
	repoName := ConfigRepoName(appName, cluster)
	return "https://" + viper.GetString("GIT.CFG_USERNAME") + ":" + viper.GetString("GIT.CFG_PASSWORD") + "@" + viper.GetString("GIT.DOMAIN") + "/" + viper.GetString("GIT.CFG_USERNAME") + "/" + repoName, nil
}

func ConfigRepoName(name, cluster string) string {
	return name + "-" + cluster
}

func request(url, method string, body []byte) error {
	log.Printf("--- REQUEST URL: %s", url)
	log.Printf("--- REQUEST METHOD: %s", method)

	req, err := http.NewRequest(method, url, bytes.NewBuffer(body))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "token "+viper.GetString("GIT.ACCESS_TOKENS"))

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	log.Printf("--- RESPONSE STATUS: %s", resp.Status)

	respBody, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	log.Printf("--- RESPONSE BODY: %s", string(respBody))

	if resp.StatusCode >= 400 {
		return fmt.Errorf("request failed with status: %s", resp.Status)
	}

	return nil
}

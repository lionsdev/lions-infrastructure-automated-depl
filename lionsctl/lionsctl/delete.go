package lionsctl

import (
	"context"
	"fmt"
	"net/url"

	"dagger.io/dagger"
	"github.com/spf13/viper"
)

func Delete(ctx context.Context, client *dagger.Client, name, cluster string) error {

	fmt.Println("--- DELETE REPOSITORY")

	repoName := ConfigRepoName(name, cluster)

	apiUri, err := url.JoinPath(viper.GetString("GIT.BASE_URL"), viper.GetString("GIT.REPO_API_ENDPOINT"), viper.GetString("GIT.CFG_USERNAME"), repoName)
	if err != nil {
		return err
	}

	return request(apiUri, "DELETE", nil)
}
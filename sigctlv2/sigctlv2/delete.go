package sigctlv2

import (
	"context"
	"net/url"

	"dagger.io/dagger"
	"github.com/spf13/viper"
)

type DeleteOptions struct {
	AppName string
	Cluster string
}

func Delete(ctx context.Context, client *dagger.Client, opts DeleteOptions) error {
	repoName := ConfigRepoName(opts.AppName, opts.Cluster)
	apiUri, err := url.JoinPath(viper.GetString("GIT.BASE_URL"), viper.GetString("GIT.REPO_API_ENDPOINT"), "sigctl", repoName)
	if err != nil {
		return err
	}
	return request(apiUri, "DELETE", []byte{})
}

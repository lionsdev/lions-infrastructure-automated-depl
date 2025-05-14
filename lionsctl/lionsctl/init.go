package lionsctl

import (
	"context"
	"embed"
	"encoding/json"
	"log"
	"net/url"
	"os"
	"path"

	"dagger.io/dagger"
	"github.com/spf13/viper"
)

type CreateGitRepoOptions struct {
	AutoInit      bool   `json:"auto_init"`
	DefaultBranch string `json:"default_branch"`
	Description   string `json:"description"`
	Gitignores    string `json:"gitignores"`
	IssueLabels   string `json:"issue_labels"`
	License       string `json:"license"`
	Name          string `json:"name"`
	Private       bool   `json:"private"`
	Readme        string `json:"readme"`
	Template      bool   `json:"template"`
	TrustModel    string `json:"trust_model"`
}

func NewCreateGitRepoOtions(name, cluster, defaultBranch string, autoInit bool) CreateGitRepoOptions {
	return CreateGitRepoOptions{
		AutoInit:      autoInit,
		DefaultBranch: defaultBranch,
		Description:   "",
		Gitignores:    "",
		IssueLabels:   "",
		License:       "",
		Name:          ConfigRepoName(name, cluster),
		Private:       false,
		Readme:        "",
		Template:      true,
		TrustModel:    "",
	}
}

func CreateConfig(ctx context.Context, client *dagger.Client, opts *CreateGitRepoOptions) error {

	apiUri, err := url.JoinPath(viper.GetString("GIT.BASE_URL"), viper.GetString("GIT.USER_API_ENDPOINT"))
	if err != nil {
		return err
	}

	body, err := json.Marshal(opts)
	if err != nil {
		return err
	}
	return request(apiUri, "POST", body)
}

type InitRepoOptions struct {
	Ingress bool
	Volume  bool
	AppName string
	Cluster string
}

const (
	DEPLOYMENT             = "deployment.yaml"
	DEPLOYMENT_WITH_VOLUME = "deployment-with-volume.yaml"
	INGRESS                = "ingress.yaml"
	INGRESS_K1             = "ingress-k1.yaml"
	INGRESS_K2             = "ingress-k2.yaml"
	PVC                    = "pvc.yaml"
)

//go:embed base
var baseFs embed.FS

//go:embed add-ons
var addOnsFs embed.FS

func InitRepo(ctx context.Context, client *dagger.Client, opts InitRepoOptions) error {

	repoDir, err := os.MkdirTemp("", "starter")
	if err != nil {
		return err
	}
	log.Printf("---CONFIG TEMP DIR: %s", repoDir)

	err = appendBaseFiles(repoDir)
	if err != nil {
		return err
	}
	err = appendAddOnsFiles(repoDir, opts)
	if err != nil {
		return err
	}

	err = updateConfigRepo(ctx, client, repoDir, opts)
	if err != nil {
		return err
	}

	return nil

}

func appendBaseFiles(repoDir string) error {

	baseFsName := "base"

	baseEntries, err := baseFs.ReadDir(baseFsName)
	if err != nil {
		return err
	}
	log.Printf("---BASE FOLDER SIZE: %d", len(baseEntries))

	for _, entry := range baseEntries {
		log.Printf("---CURRENT ENTRY: %s", entry.Name())
		if !entry.IsDir() {
			srcPath := path.Join(baseFsName, entry.Name())
			destPath := path.Join(repoDir, entry.Name())

			err = copyFile(srcPath, destPath, baseFs)
			if err != nil {
				return err
			}

		} else {

			srcDir := path.Join(baseFsName, entry.Name())
			destDir := path.Join(repoDir, entry.Name())

			err = copyDir(srcDir, destDir, baseFs)
			if err != nil {
				return err
			}

		}
	}

	return nil
}

func appendAddOnsFiles(repoDir string, opts InitRepoOptions) error {

	addOnsFsName := "add-ons"
	ingressFle := INGRESS_K2

	if opts.Ingress {
		if opts.Cluster == "k1" {
			ingressFle = INGRESS_K1
		}
		srcPath := path.Join(addOnsFsName, ingressFle)
		destPath := path.Join(repoDir, "templates", INGRESS)
		err := copyFile(srcPath, destPath, addOnsFs)
		if err != nil {
			return err
		}
	}

	if opts.Volume {
		volSrcPath := path.Join(addOnsFsName, PVC)
		volDestPath := path.Join(repoDir, "templates", PVC)
		err := copyFile(volSrcPath, volDestPath, addOnsFs)
		if err != nil {
			return err
		}

		srcPath := path.Join(addOnsFsName, DEPLOYMENT_WITH_VOLUME)
		destPath := path.Join(repoDir, "templates", DEPLOYMENT)
		err = copyFile(srcPath, destPath, addOnsFs)
		if err != nil {
			return err
		}
	} else {
		srcPath := path.Join(addOnsFsName, DEPLOYMENT)
		destPath := path.Join(repoDir, "templates", DEPLOYMENT)
		err := copyFile(srcPath, destPath, addOnsFs)
		if err != nil {
			return err
		}
	}

	return nil
}

func copyFile(src, dst string, fs embed.FS) error {

	log.Printf("--- COPY FILE SOURCE: %s", src)
	log.Printf("--- COPY FILE DEST: %s", dst)
	content, err := fs.ReadFile(src)
	if err != nil {
		return err
	}

	destFile, err := os.Create(dst)
	if err != nil {
		return err
	}

	_, err = destFile.Write(content)
	if err != nil {
		return err
	}

	destFile.Close()

	return nil
}

func copyDir(srcDir, dstDir string, fs embed.FS) error {

	log.Printf("--- COPY DIR SOURCE: %s", srcDir)
	log.Printf("--- COPY DIR DEST: %s", dstDir)

	err := os.MkdirAll(dstDir, 0755)
	if err != nil {
		return err
	}

	tplDirEntry, err := fs.ReadDir(srcDir)
	if err != nil {
		return err
	}

	for _, tplEntry := range tplDirEntry {

		filePath := path.Join(srcDir, tplEntry.Name())
		tplDest := path.Join(dstDir, tplEntry.Name())

		copyFile(filePath, tplDest, fs)

	}

	return nil
}

func updateConfigRepo(ctx context.Context, client *dagger.Client, repoDir string, opts InitRepoOptions) error {

	gitName := ConfigRepoName(opts.AppName, opts.Cluster)

	pushUrl := "https://" + viper.GetString("GIT.CFG_USERNAME") + ":" + viper.GetString("GIT.CFG_PASSWORD") +
		"@" + viper.GetString("GIT.DOMAIN") +
		"/" + viper.GetString("GIT.CFG_USERNAME") + "/" + gitName
	log.Printf("---PUSH URL: %s", pushUrl)

	src := client.Host().Directory(repoDir)

	git := client.Container().
		From("alpine/git:2.36.3").
		WithDirectory("/src", src).
		WithWorkdir("/src").
		WithExec([]string{"config", "--global", "user.email", viper.GetString("GIT.CFG_EMAIL")}).
		WithExec([]string{"config", "--global", "user.name", viper.GetString("GIT.CFG_USERNAME")}).
		WithExec([]string{"init", "-b", viper.GetString("GIT.CFG_DEFAULT_BRNCH")}).
		WithExec([]string{"add", "."}).
		WithExec([]string{"commit", "-m", "initial commit"})

	prodBranch := "default"
	if opts.Cluster == "k2" {
		prodBranch = "prod"
	}

	for _, bch := range []string{prodBranch, "preprod", "debug"} {
		git = git.WithExec([]string{"checkout", "-b", bch})
	}

	git = git.WithExec([]string{"remote", "add", "origin", pushUrl}).
		WithExec([]string{"push", "origin", "--all"})

	_, err := git.Stdout(ctx)
	if err != nil {
		return err
	}

	return nil
}
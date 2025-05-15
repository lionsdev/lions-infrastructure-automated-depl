package sigctlv2

import (
	"context"
	"fmt"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
	"github.com/pterm/pterm"
)

type ClearOptions struct {
}

func Clear(tx context.Context, opts ClearOptions) error {

	pterm.Info.Println("===============================[ CLEARING ENGINE ]===============================")

	ctx := context.Background()
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return err
	}

	defer cli.Close()

	f := filters.NewArgs()
	f.Add("name", "dagger-engine-*")

	containers, err := cli.ContainerList(ctx, types.ContainerListOptions{
		Filters: f,
	})
	if err != nil {
		return err
	}

	var containerID string
	//var imageID string

	for _, container := range containers {
		fmt.Println(container.ID + " " + container.Image)
		containerID = container.ID
		//imageID = container.ImageID
		break
	}

	if containerID != "" {
		err = cli.ContainerStop(ctx, containerID, container.StopOptions{
			Timeout: nil,
		})
		if err != nil {
			return err
		}

		err = cli.ContainerRemove(ctx, containerID, types.ContainerRemoveOptions{
			RemoveVolumes: true,
			Force:         true,
		})
		if err != nil {
			return err
		}
	}

	pterm.Success.Println("===============================[ CLEARING ENGINE SUCCEEDED ]===============================")

	return nil
}

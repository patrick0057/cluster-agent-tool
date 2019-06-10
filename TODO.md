1. Create function / option to delete all rancher agents.

```bash
docker ps -a | grep rancher-agent | awk '{print $1}' | xargs docker stop; docker stop kubelet ; docker stop kube-proxy && sleep 1
docker ps -a | grep rancher-agent | awk '{print $1}' | xargs docker rm
```

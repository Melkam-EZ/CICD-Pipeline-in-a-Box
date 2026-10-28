# Diagram prompt (copy everything below into an image-generation model)

Create a clean, professional cloud infrastructure diagram, 16:9 landscape, white background, flat vector style, large readable labels, thin dark-grey lines, soft pastel fills. Title at the top: "CI/CD Pipeline in a Box: everything on one EC2 instance".

LAYOUT, left to right.

LEFT: a "Developer laptop" box containing three small items: "git push", "Browser (Gitea UI)", "SSH client". A dashed arrow labeled "SSH tunnel (port 22) for ports 3000, 5000, 8081" and a solid arrow labeled "git push (through the tunnel)" go to the right.

MIDDLE: a thin firewall icon labeled "Security group: inbound SSH 22 from my IP only; all other ports closed".

RIGHT: a large AWS-orange-bordered box labeled "AWS Region > Default VPC > EC2 instance m7i-flex.large (Ubuntu 24.04, 2 vCPU, 8 GiB)". Inside it, one big blue rounded box labeled "Docker Engine (Docker Compose stack: cicd-box)". Inside the Docker box, place:
1. "Gitea (Git server + Actions) :3000" with a small SQLite database icon.
2. "CI Runner (Gitea act_runner, host network, mounts docker.sock)".
3. "Local Docker Registry :5000".
4. A group labeled "Deployed app" with two containers: "hello-app LIVE :8081" (green) and "hello-app CANDIDATE :8082" (yellow, dashed border).

Numbered arrows between components, each with a short label:
1. Developer pushes code to Gitea.
2. Gitea queues the pipeline job for the runner.
3. Runner clones the repo from Gitea.
4. Runner runs unit tests (docker build, test stage).
5. Runner builds the image and pushes hello-app:<commit-sha> to the Local Registry.
6. Runner starts the CANDIDATE container and health-checks it.
7. If healthy: runner replaces the LIVE container (green arrow). If unhealthy: candidate is deleted and LIVE keeps serving (red arrow with an X).
8. Developer opens the live app through the tunnel.

Add a small legend: green = healthy/live, yellow = candidate, red = blocked deploy. Add a footer note: "No other AWS services. Registry and Git server are simulated locally on the same instance."

Do not add any AWS services that are not listed (no S3, ECR, IAM, ALB, RDS). Use generic icons, no brand logos other than a simple Docker whale and a generic git branch icon. Make sure all text is spelled exactly as written above.

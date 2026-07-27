resource "aws_iam_role_policy_attachment" "worker_ecr_attach" {
  role       = aws_iam_role.worker_route53_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

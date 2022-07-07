# Iam Resources
resource "aws_iam_user" "falco" {
  name = "falco"
}

resource "aws_iam_access_key" "falco" {
  user = aws_iam_user.falco.name
}

resource "aws_iam_user_policy_attachment" "test-attach" {
  user       = aws_iam_user.falco.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
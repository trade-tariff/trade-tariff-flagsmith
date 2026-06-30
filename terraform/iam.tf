data "aws_iam_policy_document" "task" {
  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ses:GetSendQuota",
      "ses:SendEmail",
      "ses:SendRawEmail",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "task" {
  name   = "flagsmith-task-role-policy-${var.environment}"
  policy = data.aws_iam_policy_document.task.json
}

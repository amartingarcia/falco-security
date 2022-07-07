# SNS Resources
resource "aws_sns_topic_policy" "allow_cloudtrail_publish" {
  arn    = aws_sns_topic.cloudtrail.arn
  policy = data.aws_iam_policy_document.cloudtrail_sns.json
}

resource "aws_sns_topic" "cloudtrail" {
  name = var.name
  tags = var.tags
}

data "aws_iam_policy_document" "cloudtrail_sns" {
  statement {
    sid    = "AllowCloudtrailPublish"
    effect = "Allow"
    principals {
      identifiers = ["cloudtrail.amazonaws.com"]
      type        = "Service"
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.cloudtrail.arn]
  }

  # Organizational Requirements
  # note; this statement is required to be on the SNS creation, don't move to other module as policies cannot be overriten/exteneded after creation
  dynamic "statement" {
    for_each = var.is_organizational ? [1] : []
    content {
      sid    = "AllowFalcosecurityForCloudSubscribe"
      effect = "Allow"
      principals {
        identifiers = ["arn:aws:iam::${var.organizational_config.falcosecurity_for_cloud_member_account_id}:role/${var.organizational_config.organizational_role_per_account}"]
        type        = "AWS"
        #        more open policy but without requiring aws provider role
        #        identifiers = ["sqs.amazonaws.com"]
        #        type        = "Service"
      }
      actions   = ["sns:Subscribe"]
      resources = [aws_sns_topic.cloudtrail.arn]
    }
  }
}

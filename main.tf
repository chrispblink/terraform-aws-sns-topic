data "aws_caller_identity" "current" {}

module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.15.0"
  namespace  = var.namespace
  name       = var.name
  stage      = var.stage
  attributes = var.attributes
}

resource "aws_sns_topic" "this" {
  name              = module.label.id
  display_name      = module.label.id
  kms_master_key_id = var.kms_master_key_id
}

resource "aws_sns_topic_subscription" "this" {
  for_each = var.subscribers

  topic_arn              = aws_sns_topic.this.arn
  protocol               = var.subscribers[each.key].protocol
  endpoint               = var.subscribers[each.key].endpoint
  endpoint_auto_confirms = var.subscribers[each.key].endpoint_auto_confirms
  # TODO enable when PR gets merged https://github.com/terraform-providers/terraform-provider-aws/issues/10931
  # redrive_policy        = length(aws_sqs_queue.dead_letter_queue.*) > 0 ? "{\"deadLetterTargetArn\": \"${join("", aws_sqs_queue.dead_letter_queue.*.arn)}\"}" : null
}

resource "aws_sns_topic_policy" "this" {
  arn    = aws_sns_topic.this.arn
  policy = length(var.sns_topic_policy_json) > 0 ? var.sns_topic_policy_json : data.aws_iam_policy_document.aws_sns_topic_policy.json
}

data "aws_iam_policy_document" "aws_sns_topic_policy" {
  policy_id = "SNSTopicsPub"
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this.arn]

    principals {
      type        = "Service"
      identifiers = var.allowed_aws_services_for_sns_published
    }
  }
}


# TODO enable when PR gets merged https://github.com/terraform-providers/terraform-provider-aws/issues/10931
resource "aws_sqs_queue" "dead_letter_queue" {
  count = var.sqs_dlq_enabled ? 1 : 0

  name                      = module.label.id
  max_message_size          = var.sqs_dlq_max_message_size
  message_retention_seconds = var.sqs_dlq_message_retention_seconds
}

data "aws_iam_policy_document" "sqs-queue-policy" {
  count = var.sqs_dlq_enabled ? 1 : 0

  policy_id = "${join("", aws_sqs_queue.dead_letter_queue.*.arn)}/SNSDeadLetterQueue"

  statement {
    effect    = "Allow"
    actions   = ["SQS:SendMessage"]
    resources = [join("", aws_sqs_queue.dead_letter_queue.*.arn)]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.this.arn]
    }
  }
}

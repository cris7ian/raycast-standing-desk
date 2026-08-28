#!/bin/bash

set -euo pipefail

site_domain="standingdesk.salsaparapizza.com"
site_bucket="$site_domain"
site_profile="${AWS_PROFILE:-personal}"
site_source_dir="${1:-app-store-release-prep/web}"

for page in index.html privacy.html support.html; do
  if [[ ! -f "$site_source_dir/$page" ]]; then
    echo "Missing required page: $site_source_dir/$page" >&2
    exit 1
  fi
done

distribution_id="$({
  aws cloudfront list-distributions \
    --profile "$site_profile" \
    --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$site_domain')].Id | [0]" \
    --output text
} 2>/dev/null)"

if [[ -z "$distribution_id" || "$distribution_id" == "None" ]]; then
  echo "No CloudFront distribution found for $site_domain" >&2
  exit 1
fi

for page in index.html privacy.html support.html; do
  aws s3 cp "$site_source_dir/$page" "s3://$site_bucket/$page" \
    --profile "$site_profile" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "no-cache,max-age=0,must-revalidate" \
    --only-show-errors
done

invalidation_id="$({
  aws cloudfront create-invalidation \
    --distribution-id "$distribution_id" \
    --paths "/*" \
    --profile "$site_profile" \
    --query "Invalidation.Id" \
    --output text
})"

aws cloudfront wait invalidation-completed \
  --distribution-id "$distribution_id" \
  --id "$invalidation_id" \
  --profile "$site_profile"

echo "Published https://$site_domain/"
echo "Published https://$site_domain/privacy.html"
echo "Published https://$site_domain/support.html"

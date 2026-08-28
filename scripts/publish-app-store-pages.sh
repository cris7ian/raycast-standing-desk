#!/bin/bash

set -euo pipefail

site_domain="standingdesk.salsaparapizza.com"
site_bucket="$site_domain"
site_profile="${AWS_PROFILE:-personal}"
site_source_dir="${1:-app-store-release-prep/web}"

required_files=(
  index.html
  privacy.html
  support.html
  styles.css
  robots.txt
  sitemap.xml
  site.webmanifest
  assets/app-icon.png
  assets/app-main.png
  assets/app-settings.png
  assets/og.png
)

for site_file in "${required_files[@]}"; do
  if [[ ! -f "$site_source_dir/$site_file" ]]; then
    echo "Missing required site file: $site_source_dir/$site_file" >&2
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

aws s3 sync "$site_source_dir/" "s3://$site_bucket/" \
  --profile "$site_profile" \
  --exclude "*.html" \
  --exclude "robots.txt" \
  --exclude "sitemap.xml" \
  --exclude "site.webmanifest" \
  --cache-control "public,max-age=300" \
  --only-show-errors

for site_page in index.html privacy.html support.html; do
  aws s3 cp "$site_source_dir/$site_page" "s3://$site_bucket/$site_page" \
    --profile "$site_profile" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "no-cache,max-age=0,must-revalidate" \
    --only-show-errors
done

aws s3 cp "$site_source_dir/robots.txt" "s3://$site_bucket/robots.txt" \
  --profile "$site_profile" \
  --content-type "text/plain; charset=utf-8" \
  --cache-control "no-cache,max-age=0,must-revalidate" \
  --only-show-errors

aws s3 cp "$site_source_dir/sitemap.xml" "s3://$site_bucket/sitemap.xml" \
  --profile "$site_profile" \
  --content-type "application/xml; charset=utf-8" \
  --cache-control "no-cache,max-age=0,must-revalidate" \
  --only-show-errors

aws s3 cp "$site_source_dir/site.webmanifest" "s3://$site_bucket/site.webmanifest" \
  --profile "$site_profile" \
  --content-type "application/manifest+json" \
  --cache-control "no-cache,max-age=0,must-revalidate" \
  --only-show-errors

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

for site_path in \
  "" \
  privacy.html \
  support.html \
  styles.css \
  robots.txt \
  sitemap.xml \
  site.webmanifest \
  assets/app-icon.png \
  assets/og.png; do
  curl --fail --silent --show-error --output /dev/null "https://$site_domain/$site_path"
done

curl --fail --silent --show-error "https://$site_domain/" \
  | grep --fixed-strings --quiet "Use your desk"

curl --fail --silent --show-error --head "https://$site_domain/site.webmanifest" \
  | tr -d '\r' \
  | grep --extended-regexp --ignore-case --quiet '^content-type: application/manifest\+json'

echo "Published https://$site_domain/"
echo "Published https://$site_domain/privacy.html"
echo "Published https://$site_domain/support.html"
echo "CloudFront invalidation: $invalidation_id"

#!/bin/bash
# Debug AAP API connectivity
# Run this to troubleshoot AAP API issues

echo "=== AAP API Debug Tool ==="
echo ""

# Get AAP info
AAP_NS="aap"
AAP_ROUTE=$(oc get route -n $AAP_NS -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
AAP_URL="https://$AAP_ROUTE"
AAP_USERNAME="admin"

echo "AAP namespace: $AAP_NS"
echo "AAP route: $AAP_ROUTE"
echo "AAP URL: $AAP_URL"
echo ""

# Get password
AAP_PASSWORD=$(oc get secret -n $AAP_NS aap-admin-password -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)

if [ -z "$AAP_PASSWORD" ]; then
    echo "❌ Could not get AAP password"
    exit 1
fi

echo "✅ AAP password found"
echo ""

# Test 1: Ping AAP
echo "1. Testing AAP connectivity..."
PING_RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" "$AAP_URL/api/v2/ping/" 2>&1)
echo "   HTTP Status: $PING_RESPONSE"

if [ "$PING_RESPONSE" = "200" ]; then
    echo "   ✅ AAP is reachable"
else
    echo "   ❌ AAP not reachable"
fi
echo ""

# Test 2: Test auth
echo "2. Testing authentication..."
AUTH_RESPONSE=$(curl -k -s "$AAP_URL/api/v2/me/" \
    -u "$AAP_USERNAME:$AAP_PASSWORD" 2>&1)

echo "   Response:"
echo "$AUTH_RESPONSE" | jq '.' 2>/dev/null || echo "$AUTH_RESPONSE"
echo ""

# Test 3: Get job templates with full response
echo "3. Getting job templates..."
JT_RESPONSE=$(curl -k -s "$AAP_URL/api/v2/job_templates/" \
    -u "$AAP_USERNAME:$AAP_PASSWORD" 2>&1)

echo "   Full response:"
echo "$JT_RESPONSE" | jq '.' 2>/dev/null || echo "$JT_RESPONSE"
echo ""

# Test 4: Try with verbose curl
echo "4. Verbose curl test..."
curl -k -v "$AAP_URL/api/v2/job_templates/?page_size=100" \
    -u "$AAP_USERNAME:$AAP_PASSWORD" 2>&1 | head -50

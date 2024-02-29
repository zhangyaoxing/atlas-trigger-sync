#!/bin/bash
source ./color.sh
source ./api.sh

if [ -z $public_key ]; then
    read -p "Enter source public key: " public_key
fi
if [ -z $private_key ]; then
    read -p "Enter source private key: " private_key
fi

project_id="634d2577efd94923c95f62a7"
app_id="65254a36ad5e148927de584b"

# Login using public/private key and get access token.
# The token will be used for the rest part of this script.
echo -e "Loging in with public key and private key."
echo '{"username": "'$public_key'", "apiKey": "'$private_key'"}' > _temp.json
auth_result=`api_post _temp.json 'https://realm.mongodb.com/api/admin/v3.0/auth/providers/mongodb-cloud/login'`
token=`echo -E "$auth_result" | jq -r .access_token`
if [ $token = null ]; then
    echo -e "${RED}Login failed!${NC}"
    echo -e "${RED}$auth_result${NC}"
    exit 1
fi
echo -e "${GREEN}Login OK!${NC}"
auth_header="Authorization: Bearer $token"

# Get all triggers
echo "Retrieving all trigger definitions from source cluster."
triggers=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/triggers?product=atlas"`
if [ $? != 0 ]; then
    echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
    exit 1;
elif [ `echo -E "$triggers" | jq -r type` != "array" ]; then
    echo -e "${RED}Error getting triggers${NC}"
    echo -e "${RED}${triggers}${NC}"
    exit 1
fi
echo -E "$triggers" > triggers.json
echo -e "${GREEN}Trigger definitions are written to: ${CYAN}triggers.json${NC}"

# Get all trigger functions
echo "Retrieving all trigger functions from source cluster."

rm -f functions.json
echo -E "$triggers" | jq -c ".[]" |
while IFS=$"\n" read -r fun; do
    fid=`echo -E "$fun" | jq -r .function_id`
    fname=`echo -E "$fun" | jq -r .function_name`
    echo -e -n "Retrieving function definition: ${YELLOW}$fname${NC}"
    # Retrieve function by function_id
    fdef=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/functions/${fid}?product=atlas"`
    # curl -s --request GET --header "$auth_header" "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/functions/${fid}?product=atlas"
    if [ $? != 0 ]; then
        echo -e "${RED} [Error]${NC}"
        echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
        exit 1;
    elif [ `echo -E "$fdef" | jq -r type` != "object" ] || [ `echo -E "$fdef" | jq -r ._id` = "null" ]; then
        echo -e "${RED} [Error]${NC}"
        echo -e "${RED}$fdef${NC}"
        exit 1
    fi
    echo -E "$fdef" >> functions.json
    echo -e "${GREEN} [Done]${NC}"
done
if [ $? != 0 ]; then exit 1; fi
echo -e "${GREEN}All trigger functions written to: ${CYAN}functions.json${NC}"
# cleanup
rm -f _temp.json
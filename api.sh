#!/bin/bash
function api_get() {
    result=`curl -s --request GET --header "$auth_header" "$1"`
    if ! jq -e . >/dev/null 2>&1 <<< "$result"; then
        return 1
    fi

    echo -E "$result"
}

function api_post() {
    cmd='curl -s --request POST --header "Content-Type: application/json" --header "Accept: application/json" --header "'$auth_header'" --data '@$1" '$2'"
    result=`eval $cmd`
    if ! jq -e . >/dev/null 2>&1 <<< "$result"; then
        return 1
    fi

    echo -E "$result"
}

function api_put() {
    cmd='curl -s --request PUT --header "Content-Type: application/json" --header "Accept: application/json" --header "'$auth_header'" --data '@$1" '$2'"
    result=`eval $cmd`
    if ! jq -e . >/dev/null 2>&1 <<< "$result"; then
        return 1
    fi

    echo -E "$result"
}

function api_delete() {
    cmd='curl -s --request DELETE --header "Content-Type: application/json" --header "Accept: application/json" --header "'$auth_header'" '"$1"
    result=`eval $cmd`
    if ! jq -e . >/dev/null 2>&1 <<< "$result"; then
        return 1
    fi

    echo -E "$result"
}
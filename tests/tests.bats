load helpers/mocks/stub

@test "make sure --help works" {
    run ./platform-configure.sh -h
    [ "$status" = 0 ]
    [[ "$output" =~ "Show this help text" ]]
}

@test "bail out if root access is missing" {
    run ./platform-configure.sh
    [ "$status" = 2 ]
    [ "$output" = "Can not run without root permissions." ]
}

@test "make sure --osupdate works" {
    skip "this needs some mocks"
    stub id '-u : echo 0'
    run ./platform-configure.sh -o
    [ "$status" = 0 ]
}

@test "make sure --reboot works" {
    skip "this needs some mocks"
    run ./platform-configure.sh -r
    [ "$status" = 0 ]
}

@test "make sure --reload works" {
    skip "this needs some mocks"
    run ./platform-configure.sh -l
    [ "$status" = 0 ]
}

@test "make sure --channel works" {
    skip "this needs some mocks"
    run ./platform-configure.sh -c test123
    [ "$status" = 0 ]
}

@test "make sure --group works" {
    skip "this needs some mocks"
    run ./platform-configure.sh -g
    [ "$status" = 0 ]
}

@test "make sure --debug works" {
    skip "this needs some mocks"
    run ./platform-configure.sh -d
    [ "$status" = 0 ]
}



#!/bin/python3

# Simple script to automate pass creation
# Creates an empty main file in program/ and a file in world*/ that includes the main file

import argparse
import os

def add_dimension_files(paths, name):
    with open(paths[1], 'w') as file:
        file.write('#version 460 compatibility\n#define DIMENSION_OVERWORLD\n\n#include \"/program/' + name + '\"')

    with open(paths[2], 'w') as file:
        file.write('#version 460 compatibility\n#define DIMENSION_END\n\n#include \"/program/' + name + '\"')

    with open(paths[3], 'w') as file:
        file.write('#version 460 compatibility\n#define DIMENSION_NETHER\n\n#include \"/program/' + name + '\"')


def add_pass(args):
    name = args.name
    # Check if file exists and exit to prevent accidental overwrites
    paths = ["shaders/program/" + name, "shaders/world0/" + name, "shaders/world1/" + name, "shaders/world-1/" + name]
    for path in paths:
        if os.path.exists(path):
            print("This file already exists!")
            exit(1)

    with open(paths[0], 'w') as file:
        pass

    add_dimension_files(paths, name)

    print(f"File '{name}' created successfully.")

def del_pass(args):
    name = args.name
    paths = ["shaders/program/", "shaders/world0/", "shaders/world1/", "shaders/world-1/"]
    for path in paths:
        f = path + name
        if os.path.exists(f):
            os.remove(f)
    print(f"File '{name}' deleted successfully.")

def rename_pass(args):
    old_name = args.old_name
    new_name = args.new_name
    paths = ["shaders/program/", "shaders/world0/", "shaders/world1/", "shaders/world-1/"]
    for path in paths:
        new_path = path + new_name
        if os.path.exists(new_path):
            print("There's already a file with this name!")
            exit(1)
    # Move generic file
    old_path = paths[0] + old_name
    new_path = paths[0] + new_name
    if os.path.exists(old_path):
        os.rename(old_path, new_path)
    # Delete old dimension files
    for path in paths[1:]:
        f = path + old_name
        if os.path.exists(f):
            os.remove(f)
    # Create new dimension files
    add_dimension_files(list(map(lambda x : x + new_name, paths)), new_name)
        
    print(f"File {old_name} renamed to {new_name} successfully")



if __name__=="__main__":
    # Check if we are in the root directory
    current_path = os.getcwd()
    world_path = os.path.join(current_path, "shaders/world0")
    if not os.path.isdir(world_path):
        print("You need to be in the root directory of the shader!")
        print("You are now in", current_path)
        exit(1)

    # Parse arguments
    parser = argparse.ArgumentParser(description = "Simple script to automate pass creation")

    subparser = parser.add_subparsers(dest="command", help="Command to run", required=True)

    parser_add = subparser.add_parser("add")
    parser_add.set_defaults(func = add_pass)
    parser_add.add_argument("name", metavar="name")

    parser_del = subparser.add_parser("del")
    parser_del.set_defaults(func = del_pass)
    parser_del.add_argument("name", metavar="name")

    parser_rename = subparser.add_parser("rename")
    parser_rename.set_defaults(func = rename_pass)
    parser_rename.add_argument("old_name", metavar="old_name")
    parser_rename.add_argument("new_name", metavar="new_name")

    args = parser.parse_args()
    args.func(args)


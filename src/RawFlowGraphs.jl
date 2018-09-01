# Copyright 2018 IBM Corp.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

""" Datatypes and IO for raw flow graphs.
"""
module RawFlowGraphs
export RawNode, RawPort, RawNodeAnnotationKind,
  FunctionAnnotation, ConstructAnnotation, SlotAnnotation,
  read_raw_graph, rem_literals!, rem_unused_ports

using AutoHashEquals, Parameters
using Nullables

using Catlab.Diagram

@enum(RawNodeAnnotationKind,
  FunctionAnnotation = 0,
  ConstructAnnotation = 1,
  SlotAnnotation = 2)

function Base.convert(::Type{RawNodeAnnotationKind}, s::String)
  if (s == "function") FunctionAnnotation
  elseif (s == "construct") ConstructAnnotation
  elseif (s == "slot") SlotAnnotation
  else error("Unknown annotation kind \"$s\"") end
end

@with_kw struct RawNode
  language::Dict{String,Any} = Dict{String,Any}()
  annotation::Nullable{String} = Nullable{String}()
  annotation_index::Nullable{Int} = Nullable()
  annotation_kind::RawNodeAnnotationKind = FunctionAnnotation
end

function Base.:(==)(n1::RawNode, n2::RawNode)
  n1.language == n2.language &&
  isequal(n1.annotation, n2.annotation) &&
  isequal(n1.annotation_index, n2.annotation_index) &&
  n1.annotation_kind == n2.annotation_kind
end

@with_kw struct RawPort
  language::Dict{String,Any} = Dict{String,Any}()
  annotation::Nullable{String} = Nullable{String}()
  annotation_index::Nullable{Int} = Nullable()
  value::Nullable = Nullable()
end

function Base.:(==)(p1::RawPort, p2::RawPort)
  p1.language == p2.language &&
  isequal(p1.annotation, p2.annotation) &&
  isequal(p1.annotation_index, p2.annotation_index) &&
  isequal(p1.value, p2.value)
end

# Graph pre-processing.
# FIXME: Do these functions belong here?

""" Remove literals from raw flow graph.

Removes all nodes that are literal value constructors. (Currently, such nodes
occur in raw flow graphs for R, but not Python.)
"""
function rem_literals!(d::WiringDiagram)
  literals = filter(box_ids(d)) do v
    kind = get(box(d,v).value.language, "kind", "function")
    kind == "literal"
  end
  rem_boxes!(d, literals)
  d
end

""" Remove input and output ports with no connecting wires.

This simplification is practically necessary to visualize raw flow graphs
because scientific computing functions often have dozens of keyword arguments
(which manifest as input ports).
"""
function rem_unused_ports(diagram::WiringDiagram)
  result = WiringDiagram(input_ports(diagram), output_ports(diagram))
  for v in box_ids(diagram)
    # Note: To ensure that port numbers on wires remain valid, we only remove 
    # unused ports beyond the last used port.
    b = box(diagram, v)
    last_used_input = maximum([0; [wire.target.port for wire in in_wires(diagram, v)]])
    last_used_output = maximum([0; [wire.source.port for wire in out_wires(diagram, v)]])
    unused_inputs = input_ports(b)[1:last_used_input]
    unused_outputs = output_ports(b)[1:last_used_output]
    @assert add_box!(result, Box(b.value, unused_inputs, unused_outputs)) == v
  end
  add_wires!(result, wires(diagram))
  result
end

# GraphML support.

""" Read raw flow graph from GraphML.
"""
function read_raw_graph(xml)
  GraphML.read_graphml(RawNode, RawPort, Nothing, xml)
end

function GraphML.convert_from_graphml_data(::Type{RawNode}, data::Dict)
  annotation = to_nullable(String, pop!(data, "annotation", nothing))
  annotation_index = to_nullable(Int, pop!(data, "annotation_index", nothing))
  annotation_kind_str = to_nullable(String, pop!(data, "annotation_kind", nothing))
  annotation_kind = isnull(annotation_kind_str) ? FunctionAnnotation :
    convert(RawNodeAnnotationKind, get(annotation_kind_str))
  RawNode(data, annotation, annotation_index, annotation_kind)
end

function GraphML.convert_from_graphml_data(::Type{RawPort}, data::Dict)
  annotation = to_nullable(String, pop!(data, "annotation", nothing))
  annotation_index = to_nullable(Int, pop!(data, "annotation_index", nothing))
  value = to_nullable(Any, pop!(data, "value", nothing))
  RawPort(data, annotation, annotation_index, value)
end

to_nullable(T::Type, x) = x == nothing ? Nullable{T}() : Nullable{T}(x)

# Graphviz support.
# FIXME: These methods use language-specific attributes. Perhaps there should
# be some standardization across languages.

function GraphvizWiring.node_label(node::RawNode)
  lang = node.language
  get_first(lang, ["qual_name", "function", "kind"], "?")
end

function GraphvizWiring.edge_label(port::RawPort)
  lang = port.language
  get_first(lang, ["qual_name", "class"], "")
end

function get_first(collection, keys, default)
  if isempty(keys); return default end
  get(collection, splice!(keys, 1)) do
    get_first(collection, keys, default)
  end
end

end
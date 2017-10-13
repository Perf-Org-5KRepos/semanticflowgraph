module OntologyDBs
export OntologyDB, OntologyError, concept, concepts, annotation, annotations,
  load_ontology_file, load_concepts, load_annotation, load_annotations

using DataStructures: OrderedDict
import JSON

using Catlab
using ..Ontology

# FIXME: This default configuration should not be hard-coded here.
const default_config = Dict(
  :database_url => "https://d393c3b5-9979-4183-98f4-7537a5de15f5-bluemix.cloudant.com",
  :database_name => "data-science-ontology",
  :ontology => "data-science",
)

# Data types
############

""" Ontology database, containing concepts and annotations.
"""
mutable struct OntologyDB
  config::Dict{Symbol,Any}
  concepts::Presentation
  annotations::OrderedDict{String,Annotation}
  
  function OntologyDB(config::Dict{Symbol,Any})
    new(config, Presentation(String), OrderedDict{String,Annotation}())
  end
end
OntologyDB(; kw...) = OntologyDB(merge(default_config, Dict{Symbol,Any}(kw)))

struct OntologyError <: Exception
  message::String
end

# Ontology accessors
####################

function concept(db::OntologyDB, id::String)
  if !has_generator(db.concepts, id)
    throw(OntologyError("No concept named '$id'"))
  end
  generator(db.concepts, id)
end

concepts(db::OntologyDB) = db.concepts
concepts(db::OntologyDB, ids) = [ concept(db, id) for id in ids ]

function annotation(db::OntologyDB, id)
  doc_id = annotation_document_id(id)
  if !haskey(db.annotations, doc_id)
    throw(OntologyError("No annotation named '$id'"))
  end
  db.annotations[doc_id]
end

annotations(db::OntologyDB) = values(db.annotations)
annotations(db::OntologyDB, ids) = [ annotation(db, id) for id in ids ]

function annotation_document_id(id::String)
  startswith(id, "annotation/") ? id : "annotation/$id"
end
function annotation_document_id(id::AnnotationID)
  join(["annotation", id.language, id.package, id.id], "/")
end

# Local file
############

""" Load concepts/annotations from a list of JSON documents.
"""
function load_documents(db::OntologyDB, docs)
  concept_docs = filter(doc -> doc["schema"] == "concept", docs)
  merge_presentation!(db.concepts, presentation_from_json(concept_docs))
  
  annotation_docs = filter(doc -> doc["schema"] == "annotation", docs)
  for doc in annotation_docs
    db.annotations[doc["_id"]] = annotation_from_json(doc, db.concepts)
  end
end

""" Load concepts/annotations from a local JSON file.
"""
function load_ontology_file(db::OntologyDB, filename::String)
  open(filename) do file
    load_ontology_file(db, file)
  end
end
function load_ontology_file(db::OntologyDB, io::IO)
  load_documents(db, JSON.parse(io)::Vector)
end

# Remote database
#################

""" Load concepts in ontology from remote database.
"""
function load_concepts(db::OntologyDB; ontology=nothing)
  query = Dict("schema" => "concept")
  if ontology != nothing
    query["ontology"] = ontology
  end
  docs = CouchDB.find(db.config[:database_url], db.config[:database_name], query)
  load_documents(db, docs)
end

""" Load annotations in ontology from remote database.
"""
function load_annotations(db::OntologyDB; language=nothing, package=nothing)
  query = Dict("schema" => "annotation")
  if language != nothing
    query["language"] = language
  end
  if package != nothing
    query["package"] = package
  end
  docs = CouchDB.find(db.config[:database_url], db.config[:database_name], query)
  load_documents(db, docs)
end

""" Load single annotation from remote database, if it's not already loaded.
"""
function load_annotation(db::OntologyDB, id)::Annotation
  doc_id = annotation_document_id(id)
  if haskey(db.annotations, doc_id)
    return db.annotations[doc_id]
  end
  
  doc = CouchDB.get(db.config[:database_url], db.config[:database_name], doc_id)
  if get(doc, "error", nothing) == "not_found"
    throw(OntologyError("No annotation named '$id'"))
  end
  load_documents(db, [doc])
  db.annotations[doc_id]
end

# CouchDB client
################

module CouchDB
  import JSON, HTTP

  """ CouchDB endpoint: /{db}/{docid}
  """
  function get(url::String, db::String, doc_id::String)
    response = HTTP.get("$url/$db/$(HTTP.escape(doc_id))")
    JSON.parse(response.body)
  end

  """ CouchDB endpoint: /{db}/_find
  """
  function find(url::String, db::String, selector::Associative; kwargs...)
    request = Dict{Symbol,Any}(:selector => selector)
    merge!(request, Dict(kwargs))
    body = JSON.json(request)
    
    response = HTTP.post("$url/$db/_find", body=body)   
    body = JSON.parse(response.body)
    body["docs"]
  end
  
end

end

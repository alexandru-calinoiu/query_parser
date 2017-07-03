require 'parslet'
require 'pp'

class MyParser < Parslet::Parser
	rule(:term) { match('[a-zA-Z0-9]').repeat(1) }

	rule(:space) { match('\s').repeat(1) }

	rule(:query) { (term >> space.maybe).repeat }

	root(:query)
end

MyParser.new.parse('hello world')

begin
	MyParser.new.parse('hello, world')
rescue Parslet::ParseFailed => e
	e.parse_failure_cause.ascii_tree
end

class QueryParser < Parslet::Parser
	rule(:term) { match('[^\s"]').repeat(1).as(:term) }
	rule(:quote) { str('"') }
	rule(:operator) { (str('+') | str('-')).as(:operator) }
	rule(:phrase) do
		(quote >> (term >> space.maybe).repeat >> quote).as(:phrase)
	end
	rule(:clause) { (operator.maybe >> (phrase | term)).as(:clause) }
	rule(:space) { match('\s').repeat(1) }
	rule(:query) { (clause >> space.maybe).repeat.as(:query) }
	root(:query)
end

class Clause
	attr_reader :operator, :term

	def initialize(operator, term)
		@operator = Operator.symbol(operator)
		@term = term
	end
end

class PhraseClause
	attr_reader :operator, :phrase

	def initialize(operator, phrase)
		@operator = Operator.symbol(operator)
		@phrase = phrase
	end
end

class Operator
	def self.symbol(str)
		case str
		when '+'
			:must
		when '-'
			:must_not
		when nil
			:should
		else
			raise "Unknown operator: #{str}"
		end
	end
end

class QueryTransformer < Parslet::Transform
	rule(clause: subtree(:clause)) do
		if clause[:term]
			Clause.new(clause[:operator]&.to_s, clause[:term].to_s)
		elsif clause[:phrase]
			PhraseClause.new(clause[:operator]&.to_s, clause[:phrase].map { |p| p[:term] }.join(' '))
		else
			raise "Unexpected clause type: #{clause}"
		end
	end
	rule(query: sequence(:clauses)) { Query.new(clauses) }
end

class Query
	def initialize(clauses)
		grouped = clauses.chunk { |c| c.operator }.to_h
		@should_clauses = grouped.fetch(:should, [])
		@must_not_clauses = grouped.fetch(:must_not, [])
		@must_clauses = grouped.fetch(:must, [])
	end

	def to_elasticsearch
		query = {
			query: {
				bool: {
				}
			}
		}

		bool = query[:query][:bool]
		bool[:should] = @should_clauses.map { |clause| clause_to_query(clause) } if @should_clauses.any?
		bool[:must] = @must_clauses.map { |t| clause_to_query(t) } if @must_clauses.any?
		bool[:must_not] = @must_not_clauses.map { |t| clause_to_query(t) } if @must_not_clauses.any?

		query
	end

	private

		def clause_to_query(clause)
			case clause
			when Clause
				match(clause.term)
			when PhraseClause
				match_phrase(clause.phrase)
			else
				raise "Unknown clause type: #{clause}"
			end
		end

		def match(term)
			{
				match: {
					title: {
						query: term
					}
				}
			}
		end

		def match_phrase(phrase)
			{
				match_phrase: {
					title: {
						query: phrase
					}
				}
			}
		end
end

parse_tree = QueryParser.new.parse('"cat in the hat" -green +ham')
pp parse_tree
query = QueryTransformer.new.apply(parse_tree)
pp query.to_elasticsearch

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
	rule(:term) { match('[^\s]').repeat(1).as(:term) }
	rule(:operator) { (str('+') | str('-')).as(:operator) }
	rule(:clause) { (operator.maybe >> term).as(:clause) }
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
		Clause.new(clause[:operator]&.to_s, clause[:term].to_s)
	end
	rule(query: sequence(:clauses)) { Query.new(clauses) }
end

class Query
	def initialize(clauses)
		grouped = clauses.chunk { |c| c.operator }.to_h
		@should_terms = grouped.fetch(:should, []).map(&:term)
		@must_not_terms = grouped.fetch(:must_not, []).map(&:term)
		@must_terms = grouped.fetch(:must, []).map(&:term)
	end

	def to_elasticsearch
		query = {
			query: {
				bool: {
				}
			}
		}

		bool = query[:query][:bool]
		bool[:should] = @should_terms.map { |t| match(t) } if @should_terms.any?
		bool[:must] = @must_terms.map { |t| match(t) } if @must_terms.any?
		bool[:must_not] = @must_not_terms.map { |t| match(t) } if @must_not_terms.any?

		query
	end

	private

		def match(term)
			{
				match: {
					title: {
						query: term
					}
				}
			}
		end
end

parse_tree = QueryParser.new.parse('the +cat in the -hat')
query = QueryTransformer.new.apply(parse_tree)
pp query.to_elasticsearch

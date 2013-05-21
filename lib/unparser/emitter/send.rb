module Unparser
  class Emitter
    # Emitter for send
    class Send < self

      handle :send

      INDEX_PARENS  = IceNine.deep_freeze(%w([ ]))
      NORMAL_PARENS = IceNine.deep_freeze(%w[( )])

      INDEX_REFERENCE = '[]'.freeze
      INDEX_ASSIGN    = '[]='.freeze
      ASSIGN_SUFFIX   = '='.freeze

      AMBIGOUS = [:irange, :erange].to_set.freeze

    private

      # Perform dispatch
      #
      # @return [undefined]
      #
      # @api private
      #
      def dispatch
        case selector
        when INDEX_REFERENCE
          run(Index::Reference)
        when INDEX_ASSIGN
          run(Index::Assign)
        else
          non_index_dispatch
        end
      end

      # Emit unambigous receiver
      #
      # @return [undefined]
      #
      # @api private
      #
      def emit_unambigous_receiver
        receiver = effective_receiver
        if AMBIGOUS.include?(receiver.type) or binary_receiver?
          parentheses { visit(receiver) }
          return
        end

        visit(receiver)
      end

      # Return effective receiver
      #
      # @return [Parser::AST::Node]
      #
      # @api private
      #
      def effective_receiver
        receiver = first_child
        if receiver.type == :begin && receiver.children.length == 1
          receiver = receiver.children.first
        end
        receiver
      end

      # Test for binary receiver
      #
      # @return [true]
      #   if receiver is a binary operation implemented by a method
      #
      # @return [false]
      #   otherwise
      #
      def binary_receiver?
        receiver = effective_receiver
        case receiver.type
        when :or_asgn, :and_asgn
          true
        when :send
          BINARY_OPERATORS.include?(receiver.children[1])
        else
          false
        end
      end

      # Delegate to emitter
      #
      # @param [Class:Emitter] emitter
      #
      # @return [undefined]
      #
      # @api private
      #
      def run(emitter)
        emitter.emit(node, buffer)
      end
      
      # Perform non index dispatch
      #
      # @return [undefined]
      #
      # @api private
      #
      def non_index_dispatch
        if binary?
          run(Binary)
          return
        elsif unary?
          run(Unary)
          return
        end
        emit_receiver
        emit_selector
        emit_arguments
      end

      # Return receiver
      #
      # @return [Parser::AST::Node]
      #
      # @api private
      #
      def emit_receiver
        return unless first_child
        emit_unambigous_receiver
        write(O_DOT) 
      end

      # Test for unary operator implemented as method
      #
      # @return [true]
      #   if node is a unary operator 
      #
      # @return [false]
      #   otherwise
      #
      # @api private
      #
      def unary?
        UNARY_OPERATORS.include?(children[1])
      end

      # Test for binary operator implemented as method
      #
      # @return [true]
      #   if node is a binary operator 
      #
      # @return [false]
      #   otherwise
      #
      # @api private
      #
      def binary?
        BINARY_OPERATORS.include?(children[1])
      end

      # Emit selector
      #
      # @return [undefined]
      #
      # @api private
      #
      def emit_selector
        name = selector
        if mlhs?
          name = name[0..-2]
        end
        write(name)
      end

      # Test for mlhs
      #
      # @return [true]
      #   if node is within an mlhs
      #
      # @return [false]
      #   otherwise
      #
      # @api private
      #
      def mlhs?
        assignment? && !arguments?
      end

      # Test for assigment
      #
      # @return [true]
      #   if node represents attribute / element assignment
      #
      # @return [false]
      #   otherwise
      #
      # @api private
      #
      def assignment?
        selector[-1] == ASSIGN_SUFFIX
      end

      # Return selector
      #
      # @return [String]
      #
      # @api private
      #
      def selector
        children[1].to_s
      end
      memoize :selector

      # Test for empty arguments
      #
      # @return [true]
      #   if arguments are empty
      #
      # @return [false]
      #   otherwise
      #
      # @api private
      #
      def arguments?
        arguments.any?
      end

      # Return argument nodes
      #
      # @return [Array<Parser::AST::Node>]
      #
      # @api private
      #
      def arguments
        children[2..-1]
      end

      # Emit arguments
      #
      # @return [undefined]
      #
      # @api private
      #
      def emit_arguments
        args = arguments
        return if args.empty?
        parentheses do
          delimited(args)
        end
      end

      class Index < self

      private

        # Perform dispatch
        #
        # @return [undefined]
        #
        # @api private
        #
        def dispatch
          emit_receiver
          emit_arguments
        end

        # Emit block within parentheses
        #
        # @return [undefined]
        #
        # @api private
        #
        def parentheses(&block)
          super(*INDEX_PARENS, &block)
        end

        # Emit receiver
        #
        # @return [undefined]
        #
        # @api private
        #
        def emit_receiver
          visit(first_child)
        end

        class Reference < self

        private

          # Emit arguments
          #
          # @return [undefined]
          #
          # @api private
          #
          def emit_arguments
            parentheses do
              delimited(arguments)
            end
          end
        end # Reference

        class Assign < self

          # Emit arguments
          #
          # @return [undefined]
          #
          # @api private
          #
          def emit_arguments
            index, *assignment = arguments
            parentheses do
              delimited([index])
            end
            return if assignment.empty? # mlhs
            write(WS, O_ASN, WS)
            delimited(assignment)
          end
        end # Assign

      end # Index

      class Unary < self

      private

        MAP = IceNine.deep_freeze(
          '-@' => '-',
          '+@' => '+'
        )

        # Perform dispatch
        #
        # @return [undefined]
        #
        # @api private
        #
        def dispatch
          name = selector
          write(MAP.fetch(name, name))
          emit_unambigous_receiver
        end

      end # Unary

      class Binary < self

      private

        # Return undefined
        #
        # @return [undefined]
        #
        # @api private
        #
        def dispatch
          emit_receiver
          emit_operator
          emit_right
        end

        # Emit receiver
        #
        # @return [undefined]
        #
        # @api private
        #
        def emit_receiver
          emit_unambigous_receiver
          write(O_DOT) if parentheses?
        end

        # Emit operator 
        #
        # @return [undefined]
        #
        # @api private
        #
        def emit_operator
          parens = parentheses? ? EMPTY_STRING : WS
          parentheses(parens, parens) { write(selector) }
        end

        # Return right node
        #
        # @return [Parser::AST::Node]
        #
        # @api private
        #
        def right_node
          children[2]
        end

        # Test for splat argument
        #
        # @return [true]
        #   if first argument is a splat
        #
        # @return [false]
        #   otherwise
        #
        # @api private
        #
        def splat?
          right_node.type == :splat
        end

        # Test if parentheses are needed
        #
        # @return [true]
        #   if parenthes are needed
        #
        # @return [false]
        #   otherwise
        #
        # @api private
        #
        def parentheses?
          splat? || children.length >= 4
        end
        memoize :parentheses?

        # Emit right
        #
        # @return [undefined]
        #
        # @api private
        #
        def emit_right
          node = right_node
          if parentheses?
            parentheses { delimited(children[2..-1]) }
            return
          end
          visit(node)
        end

      end # Binary

    end # Send
  end # Emitter
end # Unparser
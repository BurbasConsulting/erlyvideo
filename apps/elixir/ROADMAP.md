## Roadmap

In the long term, here are a few things we would like to add:

### Methods and functions

* Add partial function application and function pipeline (f1 + f2)
* Extend guards support in methods
* Add guards in functions and allow functions to have several clauses
* Add alias\_method, remove\_method and undef\_method
* Allow public, private and async as decorators

### Namespaces and Refinements

* Refinements
* Data copy between modules
* Improve constant lookup (and namespaces?) (currently constants are referenced by their full name)

### Others

* Dict comprehensions and get rid of inbin and inlist
* Add more OTP behaviors: supervisors, apps, fsm and events

### Optimizations

* Do not eval code when reading files instead, quickly compile them to a module
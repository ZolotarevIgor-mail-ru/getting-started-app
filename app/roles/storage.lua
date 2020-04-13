-- module for checking arguments in functions
local checks = require('checks')

-- module for working with numbers
local decnumber = require('ldecnumber')

local function init_spaces()
    local customer = box.schema.space.create(
        -- name of the space for storing customers
        'customer',
        -- extra parameters
        {
            -- format for stored tuples
            format = {
                {'customer_id', 'unsigned'},
                {'bucket_id', 'unsigned'},
                {'name', 'string'},
            },
            -- creating the space only if it doesn't exist
            if_not_exists = true,
        }
    )

    -- creating an index by customer's id
    customer:create_index('customer_id', {
        parts = {'customer_id'},
        if_not_exists = true,
    })

    customer:create_index('bucket_id', {
        parts = {'bucket_id'},
        unique = false,
        if_not_exists = true,
    })

    -- similarly, creating a space for accounts
    local account = box.schema.space.create('account', {
        format = {
            {'account_id', 'unsigned'},
            {'customer_id', 'unsigned'},
            {'bucket_id', 'unsigned'},
            {'balance', 'string'},
            {'name', 'string'},
        },
        if_not_exists = true,
    })

    -- similar indexes
    account:create_index('account_id', {
        parts = {'account_id'},
        if_not_exists = true,
    })
    account:create_index('customer_id', {
        parts = {'customer_id'},
        unique = false,
        if_not_exists = true,
    })

    account:create_index('bucket_id', {
        parts = {'bucket_id'},
        unique = false,
        if_not_exists = true,
    })
end

local function customer_add(customer)
    customer.accounts = customer.accounts or {}

    -- opening a transaction
    box.begin()

    -- inserting a tuple into the customer space
    box.space.customer:insert({
        customer.customer_id,
        customer.bucket_id,
        customer.name
    })
    for _, account in ipairs(customer.accounts) do
        -- inserting a tuple into the account space
        box.space.account:insert({
            account.account_id,
            customer.customer_id,
            customer.bucket_id,
            '0.00',
            account.name
        })
    end

    -- committing the transaction
    box.commit()
    return true
end

local function customer_update_balance(customer_id, account_id, amount)
    -- checking function arguments
    checks('number', 'number', 'string')

    -- finding the required account in the database
    local account = box.space.account:get(account_id)
    if account == nil then   -- checking if the account was found
        return nil
    end

    -- checking if the requested account belong to the customer
    if account.customer_id ~= customer_id then
        error('Invalid account_id')
    end

    -- converting a balance string to a number
    local balance_decimal = decnumber.tonumber(account.balance)
    balance_decimal = balance_decimal + amount
    if balance_decimal:isnan() then
        error('Invalid amount')
    end

    -- rounding to 2 decimal points and converting the balance
    -- back to string
    local new_balance = balance_decimal:rescale(-2):tostring()

    -- updating the balance
    box.space.account:update({ account_id }, {
        { '=', 4, new_balance }
    })

    return new_balance
end

local function customer_lookup(customer_id)
    checks('number')

    local customer = box.space.customer:get(customer_id)
    if customer == nil then
        return nil
    end
    customer = {
        customer_id = customer.customer_id;
        name = customer.name;
    }
    local accounts = {}
    for _, account in box.space.account.index.customer_id:pairs(customer_id) do
        table.insert(accounts, {
            account_id = account.account_id;
            name = account.name;
            balance = account.balance;
        })
    end
    customer.accounts = accounts;

    return customer
end

local function init(opts)
    if opts.is_master then

        -- calling the space initialization function
        init_spaces()

        box.schema.func.create('customer_add', {if_not_exists = true})
        box.schema.func.create('customer_lookup', {if_not_exists = true})
        box.schema.func.create('customer_update_balance', {if_not_exists = true})

        box.schema.role.grant('public', 'execute', 'function', 'customer_add', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'customer_lookup', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'customer_update_balance', {if_not_exists = true})
    end

    rawset(_G, 'customer_add', customer_add)
    rawset(_G, 'customer_lookup', customer_lookup)
    rawset(_G, 'customer_update_balance', customer_update_balance)

    return true
end

return {
    role_name = 'storage',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-storage',
    },
}